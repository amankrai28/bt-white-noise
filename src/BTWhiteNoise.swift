import AppKit
import CoreAudio

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    let speakerUID: String = {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bt-white-noise/device-uid")
        return (try? String(contentsOf: file, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }()

    let scriptPath =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("bin/bt-white-noise").path

    let volumeFile =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bt-white-noise-volume")

    let noiseTypeFile =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".bt-white-noise-type")

    let launchAgentPath =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/LaunchAgents/local.btnoise.whitenoise.controller.plist"
            ).path

    var statusItem: NSStatusItem!
    let menu = NSMenu()

    var toggleButton: NSButton!
    var volumeLabel: NSTextField!
    var slider: NSSlider!

    var controlWindow: NSWindow!
    var dockToggleButton: NSButton!
    var dockStatusLabel: NSTextField!
    var dockNoisePopup: NSPopUpButton!
    var dockMicCompatibilityCheckbox: NSButton!
    var dockVolumeLabel: NSTextField!
    var dockSlider: NSSlider!

    var trackedDeviceID: AudioDeviceID?
    var lastObservedVolume = -1
    var needsAudioReset = false
    var noiseIsPlaying = false
    var otherAppsRoutedToMac = false
    var pollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {

        NSApp.applicationIconImage = makeDockIcon()
        setupApplicationMenu()

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.squareLength
        )

        statusItem.autosaveName = "BTWhiteNoiseController"
        statusItem.button?.title = "♫"
        statusItem.button?.toolTip = "BT White Noise"
        statusItem.isVisible = true
        menu.delegate = self

        // START / STOP BUTTON
        let toggleItem = NSMenuItem()

        let toggleContainer = NSView(
            frame: NSRect(x: 0, y: 0, width: 270, height: 58)
        )

        toggleButton = NSButton(
            title: "▶  START WHITE NOISE",
            target: self,
            action: #selector(toggleNoise(_:))
        )

        toggleButton.frame = NSRect(
            x: 12, y: 9, width: 246, height: 40
        )

        toggleButton.isBordered = false
        toggleButton.wantsLayer = true
        toggleButton.layer?.cornerRadius = 8
        toggleButton.layer?.masksToBounds = true

        toggleContainer.addSubview(toggleButton)

        toggleItem.view = toggleContainer
        menu.addItem(toggleItem)

        // VOLUME
        let volumeItem = NSMenuItem()

        let volumeContainer = NSView(
            frame: NSRect(x: 0, y: 0, width: 270, height: 84)
        )

        volumeLabel = NSTextField(
            labelWithString: "Speaker Volume"
        )

        volumeLabel.font = NSFont.systemFont(
            ofSize: 13,
            weight: .medium
        )

        volumeLabel.frame =
            NSRect(x: 15, y: 57, width: 230, height: 18)

        volumeContainer.addSubview(volumeLabel)

        let minus = NSButton(
            title: "−",
            target: self,
            action: #selector(volumeDown(_:))
        )

        minus.frame =
            NSRect(x: 12, y: 14, width: 36, height: 30)

        volumeContainer.addSubview(minus)

        slider = NSSlider(
            value: Double(readSavedVolume()),
            minValue: 0,
            maxValue: 100,
            target: self,
            action: #selector(sliderChanged(_:))
        )

        slider.frame =
            NSRect(x: 53, y: 14, width: 158, height: 30)

        // Live control while dragging
        slider.isContinuous = true

        volumeContainer.addSubview(slider)

        let plus = NSButton(
            title: "+",
            target: self,
            action: #selector(volumeUp(_:))
        )

        plus.frame =
            NSRect(x: 218, y: 14, width: 36, height: 30)

        volumeContainer.addSubview(plus)

        volumeItem.view = volumeContainer
        menu.addItem(volumeItem)

        menu.addItem(NSMenuItem.separator())

        // ADVANCED
        let advancedItem = NSMenuItem(
            title: "Advanced",
            action: nil,
            keyEquivalent: ""
        )

        let advancedMenu = NSMenu()

        let resetItem = NSMenuItem(
            title: "Reconnect / Reset Audio",
            action: #selector(resetAudio(_:)),
            keyEquivalent: ""
        )

        resetItem.target = self
        advancedMenu.addItem(resetItem)

        let shutdownItem = NSMenuItem(
            title: "Shut Down Audio Engine",
            action: #selector(shutdownEngine(_:)),
            keyEquivalent: ""
        )

        shutdownItem.target = self
        advancedMenu.addItem(shutdownItem)

        advancedItem.submenu = advancedMenu
        menu.addItem(advancedItem)

        statusItem.menu = menu

        setupDockInterface()

        // Initial sync is read-only and never changes system audio routing.
        syncDevice()

        // Track physical speaker-button changes.
        let timer = Timer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(pollSpeaker),
            userInfo: nil,
            repeats: true
        )

        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        refresh()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.ensureLaunchAgentLoaded()

            let frameDescription =
                self.statusItem.button?.window?.frame.debugDescription
                ?? "no window"

            let message =
                "BT Noise status item visible=\(self.statusItem.isVisible) "
                + "frame=\(frameDescription)\n"

            try? message.write(
                to: URL(
                    fileURLWithPath:
                        "/tmp/btnoise-status-item-diagnostic.log"
                ),
                atomically: true,
                encoding: .utf8
            )
        }
    }


    // MARK: - Dock interface

    func makeDockIcon() -> NSImage {

        let image = NSImage(
            size: NSSize(width: 512, height: 512)
        )

        image.lockFocus()

        let background = NSBezierPath(
            roundedRect: NSRect(
                x: 24,
                y: 24,
                width: 464,
                height: 464
            ),
            xRadius: 108,
            yRadius: 108
        )

        let gradient = NSGradient(
            starting: NSColor(
                red: 0.20,
                green: 0.38,
                blue: 0.95,
                alpha: 1
            ),
            ending: NSColor(
                red: 0.52,
                green: 0.20,
                blue: 0.86,
                alpha: 1
            )
        )

        gradient?.draw(in: background, angle: -45)

        let note = "♫" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(
                ofSize: 270,
                weight: .semibold
            )
        ]

        let noteSize = note.size(withAttributes: attributes)

        note.draw(
            at: NSPoint(
                x: (512 - noteSize.width) / 2,
                y: (512 - noteSize.height) / 2 + 12
            ),
            withAttributes: attributes
        )

        image.unlockFocus()
        image.isTemplate = false

        return image
    }

    func launchctlStatus(_ arguments: [String]) -> Int32 {

        let task = Process()
        task.executableURL = URL(
            fileURLWithPath: "/bin/launchctl"
        )
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus
        } catch {
            return -1
        }
    }

    func ensureLaunchAgentLoaded() {

        let domain = "gui/\(getuid())"
        let service =
            "\(domain)/local.btnoise.whitenoise.controller"

        guard launchctlStatus(["print", service]) != 0 else {
            return
        }

        _ = launchctlStatus([
            "bootstrap",
            domain,
            launchAgentPath
        ])
    }

    func readNoiseType() -> String {

        guard let value = try? String(
            contentsOf: noiseTypeFile,
            encoding: .utf8
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
        ["white", "pink", "brown"].contains(value)
        else {
            return "white"
        }

        return value
    }

    func noiseDisplayName(_ type: String) -> String {
        switch type {
        case "pink":
            return "Pink — balanced"
        case "brown":
            return "Brown — deep"
        default:
            return "White — full spectrum"
        }
    }

    func shortNoiseName(_ type: String) -> String {
        switch type {
        case "pink": return "PINK"
        case "brown": return "BROWN"
        default: return "WHITE"
        }
    }

    func setupApplicationMenu() {

        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "BT White Noise")

        let showItem = NSMenuItem(
            title: "Show BT White Noise",
            action: #selector(showControlWindow(_:)),
            keyEquivalent: ""
        )

        showItem.target = self
        appMenu.addItem(showItem)

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    func setupDockInterface() {

        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 440,
                height: 440
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable
            ],
            backing: .buffered,
            defer: false
        )

        window.title = "BT White Noise"
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(
            "BTWhiteNoiseControlWindow"
        )
        window.center()

        guard let content = window.contentView else {
            return
        }

        let title = NSTextField(
            labelWithString: "BT White Noise"
        )

        title.font = NSFont.systemFont(
            ofSize: 25,
            weight: .bold
        )

        title.alignment = .center
        title.frame = NSRect(
            x: 24,
            y: 374,
            width: 392,
            height: 34
        )

        content.addSubview(title)

        dockStatusLabel = NSTextField(
            labelWithString: "Checking Speaker…"
        )

        dockStatusLabel.alignment = .center
        dockStatusLabel.textColor = .secondaryLabelColor
        dockStatusLabel.frame = NSRect(
            x: 24,
            y: 345,
            width: 392,
            height: 22
        )

        content.addSubview(dockStatusLabel)

        dockToggleButton = NSButton(
            title: "▶  START WHITE NOISE",
            target: self,
            action: #selector(toggleNoise(_:))
        )

        dockToggleButton.frame = NSRect(
            x: 24,
            y: 284,
            width: 392,
            height: 48
        )

        dockToggleButton.isBordered = false
        dockToggleButton.wantsLayer = true
        dockToggleButton.layer?.cornerRadius = 10
        dockToggleButton.layer?.masksToBounds = true

        content.addSubview(dockToggleButton)

        let noiseLabel = NSTextField(
            labelWithString: "Sound"
        )

        noiseLabel.font = NSFont.systemFont(
            ofSize: 13,
            weight: .medium
        )

        noiseLabel.frame = NSRect(
            x: 30,
            y: 249,
            width: 80,
            height: 20
        )

        content.addSubview(noiseLabel)

        dockNoisePopup = NSPopUpButton(
            frame: NSRect(
                x: 116,
                y: 242,
                width: 300,
                height: 30
            ),
            pullsDown: false
        )

        dockNoisePopup.addItems(withTitles: [
            "White — full spectrum",
            "Pink — balanced",
            "Brown — deep"
        ])

        dockNoisePopup.target = self
        dockNoisePopup.action = #selector(noiseTypeChanged(_:))
        dockNoisePopup.selectItem(
            withTitle: noiseDisplayName(readNoiseType())
        )

        content.addSubview(dockNoisePopup)

        dockMicCompatibilityCheckbox = NSButton(
            checkboxWithTitle:
                "Keep OpenWhispr on the MacBook microphone",
            target: nil,
            action: nil
        )

        dockMicCompatibilityCheckbox.state = .on
        dockMicCompatibilityCheckbox.toolTip =
            "When BT Noise starts, use the MacBook microphone so Bluetooth stays in high-quality speaker mode."
        dockMicCompatibilityCheckbox.frame = NSRect(
            x: 26,
            y: 204,
            width: 390,
            height: 24
        )

        content.addSubview(dockMicCompatibilityCheckbox)

        dockVolumeLabel = NSTextField(
            labelWithString: "Speaker Volume"
        )

        dockVolumeLabel.font = NSFont.systemFont(
            ofSize: 13,
            weight: .medium
        )

        dockVolumeLabel.frame = NSRect(
            x: 30,
            y: 169,
            width: 360,
            height: 20
        )

        content.addSubview(dockVolumeLabel)

        let minus = NSButton(
            title: "−",
            target: self,
            action: #selector(volumeDown(_:))
        )

        minus.frame = NSRect(
            x: 24,
            y: 121,
            width: 40,
            height: 32
        )

        content.addSubview(minus)

        dockSlider = NSSlider(
            value: Double(readSavedVolume()),
            minValue: 0,
            maxValue: 100,
            target: self,
            action: #selector(sliderChanged(_:))
        )

        dockSlider.frame = NSRect(
            x: 72,
            y: 121,
            width: 296,
            height: 32
        )

        dockSlider.isContinuous = true
        content.addSubview(dockSlider)

        let plus = NSButton(
            title: "+",
            target: self,
            action: #selector(volumeUp(_:))
        )

        plus.frame = NSRect(
            x: 376,
            y: 121,
            width: 40,
            height: 32
        )

        content.addSubview(plus)

        let resetButton = NSButton(
            title: "Reconnect Audio",
            target: self,
            action: #selector(resetAudio(_:))
        )

        resetButton.frame = NSRect(
            x: 24,
            y: 64,
            width: 392,
            height: 34
        )

        content.addSubview(resetButton)

        let note = NSTextField(
            labelWithString:
                "Closing this window keeps BT Noise and the audio engine running."
        )

        note.alignment = .center
        note.textColor = .tertiaryLabelColor
        note.font = NSFont.systemFont(ofSize: 11)
        note.frame = NSRect(
            x: 24,
            y: 27,
            width: 392,
            height: 18
        )

        content.addSubview(note)
        controlWindow = window
    }

    @objc func showControlWindow(_ sender: Any?) {
        syncDevice()
        refresh()
        controlWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {

        showControlWindow(nil)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {

        false
    }

    // MARK: - CoreAudio device lookup

    func findSpeaker() -> AudioDeviceID? {

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return nil
        }

        let count =
            Int(size) / MemoryLayout<AudioDeviceID>.size

        var devices =
            [AudioDeviceID](repeating: 0, count: count)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        ) == noErr else {
            return nil
        }

        for device in devices {

            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var uid: CFString?
            var uidSize =
                UInt32(MemoryLayout<CFString?>.size)

            let status: OSStatus =
                withUnsafeMutableBytes(of: &uid) { buffer in

                    guard let base = buffer.baseAddress else {
                        return OSStatus(-1)
                    }

                    return AudioObjectGetPropertyData(
                        device,
                        &uidAddress,
                        0,
                        nil,
                        &uidSize,
                        base
                    )
                }

            if status == noErr,
               let uidString = uid as String?,
               uidString == speakerUID {

                return device
            }
        }

        return nil
    }

    // MARK: - Real Speaker volume

    func readDeviceVolume(_ device: AudioDeviceID) -> Int? {

        var values: [Float32] = []

        // Your diagnostic showed channels 1 + 2.
        for element: UInt32 in [1, 2] {

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            guard AudioObjectHasProperty(
                device,
                &address
            ) else {
                continue
            }

            var value: Float32 = 0

            var size =
                UInt32(MemoryLayout<Float32>.size)

            if AudioObjectGetPropertyData(
                device,
                &address,
                0,
                nil,
                &size,
                &value
            ) == noErr {

                values.append(value)
            }
        }

        guard !values.isEmpty else {
            return nil
        }

        let average =
            values.reduce(0, +) / Float32(values.count)

        return Int(
            round(Double(average) * 100.0)
        )
    }

    @discardableResult
    func setDeviceVolume(
        _ device: AudioDeviceID,
        percent: Int
    ) -> Bool {

        let bounded = max(0, min(100, percent))

        var scalar =
            Float32(bounded) / 100.0

        var changedSomething = false

        for element: UInt32 in [1, 2] {

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )

            guard AudioObjectHasProperty(
                device,
                &address
            ) else {
                continue
            }

            var settable: DarwinBoolean = false

            guard AudioObjectIsPropertySettable(
                device,
                &address,
                &settable
            ) == noErr,
            settable.boolValue else {
                continue
            }

            let size =
                UInt32(MemoryLayout<Float32>.size)

            if AudioObjectSetPropertyData(
                device,
                &address,
                0,
                nil,
                size,
                &scalar
            ) == noErr {

                changedSomething = true
            }
        }

        return changedSomething
    }

    // MARK: - Saved volume

    func readSavedVolume() -> Int {

        if let text = try? String(
            contentsOf: volumeFile,
            encoding: .utf8
        ),
        let number = Int(
            text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        ) {

            return max(0, min(100, number))
        }

        return 10
    }

    func saveVolume(_ volume: Int) {

        let bounded = max(0, min(100, volume))

        try? "\(bounded)\n".write(
            to: volumeFile,
            atomically: true,
            encoding: .utf8
        )
    }


    // MARK: - Mac default-output protection

    func findAudioDevice(uid targetUID: String) -> AudioDeviceID? {

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        ) == noErr else {
            return nil
        }

        let count =
            Int(size) / MemoryLayout<AudioDeviceID>.size

        var devices =
            [AudioDeviceID](repeating: 0, count: count)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &devices
        ) == noErr else {
            return nil
        }

        for device in devices {

            var uidAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceUID,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )

            var uid: CFString?
            var uidSize =
                UInt32(MemoryLayout<CFString?>.size)

            let status: OSStatus =
                withUnsafeMutableBytes(of: &uid) { buffer in

                    guard let base = buffer.baseAddress else {
                        return OSStatus(-1)
                    }

                    return AudioObjectGetPropertyData(
                        device,
                        &uidAddress,
                        0,
                        nil,
                        &uidSize,
                        base
                    )
                }

            if status == noErr,
               let uidString = uid as String?,
               uidString == targetUID {

                return device
            }
        }

        return nil
    }


    func currentDefaultDevice(
        selector: AudioObjectPropertySelector
    ) -> AudioDeviceID? {

        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var device = AudioDeviceID(0)

        var size =
            UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )

        return status == noErr ? device : nil
    }


    @discardableResult
    func setDefaultDevice(
        _ device: AudioDeviceID,
        selector: AudioObjectPropertySelector
    ) -> Bool {

        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value = device

        let size =
            UInt32(MemoryLayout<AudioDeviceID>.size)

        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &value
        ) == noErr
    }

    @discardableResult
    func routeOtherAppsToMacSpeakers() -> Bool {

        guard let macSpeakers = findAudioDevice(
            uid: "BuiltInSpeakerDevice"
        ) else {
            return false
        }

        var succeeded = true

        for selector in [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice
        ] {
            if currentDefaultDevice(selector: selector)
                != macSpeakers {

                succeeded = setDefaultDevice(
                    macSpeakers,
                    selector: selector
                ) && succeeded
            }
        }

        return succeeded
    }


    func prepareOpenWhisprCompatibility() {

        guard dockMicCompatibilityCheckbox.state == .on,
              let speakerInput = findAudioDevice(
                uid: speakerUID.replacingOccurrences(of: ":output", with: ":input")
              ),
              let macMicrophone = findAudioDevice(
                uid: "BuiltInMicrophoneDevice"
              ),
              let currentInput = currentDefaultDevice(
                selector:
                    kAudioHardwarePropertyDefaultInputDevice
              ),
              currentInput == speakerInput
        else {
            return
        }

        _ = setDefaultDevice(
            macMicrophone,
            selector:
                kAudioHardwarePropertyDefaultInputDevice
        )
    }


    // MARK: - Speaker tracking

    func syncDevice() {

        guard let device = findSpeaker() else {

            if trackedDeviceID != nil {
                // Speaker disappeared while app was running.
                needsAudioReset = true

                // Prevent surprise playback on reconnection.
                _ = control(["stop"])
            }

            trackedDeviceID = nil

            updateConnectionUI(
                connected: false,
                volumeAvailable: false
            )

            return
        }

        let actualVolume = readDeviceVolume(device)
        let volumeAvailable = actualVolume != nil

        // New/reconnected device.
        if trackedDeviceID == nil ||
           trackedDeviceID != device {

            trackedDeviceID = device

            if let actualVolume {
                lastObservedVolume = actualVolume
                updateVolumeDisplay(actualVolume)
            } else {
                lastObservedVolume = -1
            }

            updateConnectionUI(
                connected: true,
                volumeAvailable: volumeAvailable
            )

            refresh()

            return
        }

        // Existing connection: watch the physical buttons.
        if let actual = actualVolume,
           actual != lastObservedVolume {

            lastObservedVolume = actual

            // Physical Speaker +/- changes become our new
            // remembered starting volume.
            saveVolume(actual)

            updateVolumeDisplay(actual)
        }

        updateConnectionUI(
            connected: true,
            volumeAvailable: volumeAvailable
        )
    }

    @objc func pollSpeaker() {
        syncDevice()

        if noiseIsPlaying {
            let routed = routeOtherAppsToMacSpeakers()

            if routed != otherAppsRoutedToMac {
                otherAppsRoutedToMac = routed

                updateToggleButton(
                    isOn: true,
                    connected: findSpeaker() != nil
                )
            }
        }
    }

    // MARK: - mpv control

    func control(_ arguments: [String]) -> String {

        let process = Process()
        let output = Pipe()

        process.executableURL =
            URL(fileURLWithPath: "/bin/zsh")

        process.arguments =
            [scriptPath] + arguments

        process.standardOutput = output

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        let data =
            output.fileHandleForReading
                .readDataToEndOfFile()

        return String(
            data: data,
            encoding: .utf8
        ) ?? ""
    }

    func clean(_ value: String) -> String {
        value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }

    // MARK: - UI

    func updateVolumeDisplay(_ volume: Int) {

        slider.doubleValue = Double(volume)
        dockSlider.doubleValue = Double(volume)

        volumeLabel.stringValue =
            "Speaker Volume  \(volume)%"

        dockVolumeLabel.stringValue =
            "Speaker Volume  \(volume)%"
    }

    func updateConnectionUI(
        connected: Bool,
        volumeAvailable: Bool
    ) {

        slider.isEnabled = connected && volumeAvailable
        dockSlider.isEnabled = connected && volumeAvailable

        if connected {
            if volumeAvailable,
               lastObservedVolume >= 0 {

                updateVolumeDisplay(lastObservedVolume)

            } else {
                volumeLabel.stringValue =
                    "Speaker volume temporarily unavailable"

                dockVolumeLabel.stringValue =
                    "Speaker volume temporarily unavailable"
            }

            return
        }

        if !connected {

            toggleButton.isEnabled = false
            dockToggleButton.isEnabled = false

            toggleButton.attributedTitle =
                NSAttributedString(
                    string: "SPEAKER DISCONNECTED",
                    attributes: [
                        .foregroundColor: NSColor.white,
                        .font: NSFont.systemFont(
                            ofSize: 13,
                            weight: .semibold
                        )
                    ]
                )

            toggleButton.layer?.backgroundColor =
                NSColor.systemGray.cgColor

            dockToggleButton.attributedTitle =
                NSAttributedString(
                    string: "SPEAKER DISCONNECTED",
                    attributes: [
                        .foregroundColor: NSColor.white,
                        .font: NSFont.systemFont(
                            ofSize: 14,
                            weight: .semibold
                        )
                    ]
                )

            dockToggleButton.layer?.backgroundColor =
                NSColor.systemGray.cgColor

            volumeLabel.stringValue =
                "Speaker disconnected"

            dockVolumeLabel.stringValue =
                "Speaker disconnected"

            dockStatusLabel.stringValue =
                "Speaker is disconnected"

            dockStatusLabel.textColor = .systemRed
        }
    }

    func updateToggleButton(
        isOn: Bool,
        connected: Bool
    ) {

        guard connected else {
            updateConnectionUI(
                connected: false,
                volumeAvailable: false
            )
            return
        }

        toggleButton.isEnabled = true
        dockToggleButton.isEnabled = true

        let noiseName = shortNoiseName(readNoiseType())

        let title =
            isOn
            ? "■  STOP \(noiseName) NOISE"
            : "▶  START \(noiseName) NOISE"

        let background =
            isOn
            ? NSColor.systemRed
            : NSColor.systemGreen

        toggleButton.attributedTitle =
            NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(
                        ofSize: 13,
                        weight: .semibold
                    )
                ]
            )

        toggleButton.layer?.backgroundColor =
            background.cgColor

        dockToggleButton.attributedTitle =
            NSAttributedString(
                string: title,
                attributes: [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(
                        ofSize: 14,
                        weight: .semibold
                    )
                ]
            )

        dockToggleButton.layer?.backgroundColor =
            background.cgColor

        dockStatusLabel.stringValue =
            isOn
            ? (
                otherAppsRoutedToMac
                ? "\(noiseName.capitalized) → Speaker • Other apps → MacBook"
                : "\(noiseName.capitalized) → Speaker • Check Mac audio routing"
            )
            : "Speaker connected • BT Noise is stopped"

        dockStatusLabel.textColor = .secondaryLabelColor
    }

    func refresh() {

        let state =
            clean(control(["status"]))

        let connected =
            findSpeaker() != nil

        let isOn =
            state == "on" && connected

        noiseIsPlaying = isOn
        otherAppsRoutedToMac =
            isOn ? routeOtherAppsToMacSpeakers() : false

        dockNoisePopup.selectItem(
            withTitle: noiseDisplayName(readNoiseType())
        )

        updateToggleButton(
            isOn: isOn,
            connected: connected
        )

        statusItem.button?.title =
            isOn ? "♪" : "♫"
    }

    func menuWillOpen(_ menu: NSMenu) {
        syncDevice()
        refresh()
    }

    // MARK: - Actions

    @objc func noiseTypeChanged(_ sender: NSPopUpButton) {

        let type: String

        switch sender.indexOfSelectedItem {
        case 1:
            type = "pink"
        case 2:
            type = "brown"
        default:
            type = "white"
        }

        _ = control(["select", type])
        refresh()
    }

    @objc func toggleNoise(_ sender: Any?) {

        guard let device = findSpeaker() else {
            syncDevice()
            NSSound.beep()
            return
        }

        let state =
            clean(control(["status"]))

        if state == "on" {

            _ = control(["stop"])

        } else {

            prepareOpenWhisprCompatibility()
            otherAppsRoutedToMac =
                routeOtherAppsToMacSpeakers()

            // Safety: restore remembered REAL speaker
            // volume before making audio audible.
            let saved = readSavedVolume()

            if setDeviceVolume(
                device,
                percent: saved
            ) {
                lastObservedVolume = saved
                updateVolumeDisplay(saved)
            }

            if needsAudioReset {

                _ = control(["reset"])
                needsAudioReset = false

            } else {

                _ = control(["start"])
            }
        }

        refresh()
    }

    @objc func sliderChanged(_ sender: NSSlider) {

        guard let device = findSpeaker() else {
            return
        }

        let volume =
            Int(sender.doubleValue.rounded())

        guard setDeviceVolume(
            device,
            percent: volume
        ) else {
            syncDevice()
            return
        }

        lastObservedVolume = volume

        saveVolume(volume)
        updateVolumeDisplay(volume)
    }

    @objc func volumeDown(_ sender: Any?) {

        guard let device = findSpeaker() else {
            return
        }

        let current =
            readDeviceVolume(device)
            ?? readSavedVolume()

        let volume = max(0, current - 5)

        guard setDeviceVolume(
            device,
            percent: volume
        ) else {
            syncDevice()
            return
        }

        lastObservedVolume = volume

        saveVolume(volume)
        updateVolumeDisplay(volume)
    }

    @objc func volumeUp(_ sender: Any?) {

        guard let device = findSpeaker() else {
            return
        }

        let current =
            readDeviceVolume(device)
            ?? readSavedVolume()

        let volume = min(100, current + 5)

        guard setDeviceVolume(
            device,
            percent: volume
        ) else {
            syncDevice()
            return
        }

        lastObservedVolume = volume

        saveVolume(volume)
        updateVolumeDisplay(volume)
    }

    @objc func resetAudio(_ sender: Any?) {

        guard let device = findSpeaker() else {
            NSSound.beep()
            return
        }

        let saved = readSavedVolume()

        prepareOpenWhisprCompatibility()
        otherAppsRoutedToMac =
            routeOtherAppsToMacSpeakers()

        if setDeviceVolume(
            device,
            percent: saved
        ) {
            lastObservedVolume = saved
            updateVolumeDisplay(saved)
        }

        _ = control(["reset"])

        needsAudioReset = false

        refresh()
    }

    @objc func shutdownEngine(_ sender: Any?) {

        _ = control(["shutdown"])
        needsAudioReset = false

        refresh()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
