import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Window 2.2
// Qualified so Material's control types don't replace the native macOS style's.
// Material's attached properties still apply where Material is the style.
import QtQuick.Controls.Material 2.2 as Mat

import ComputerManager 1.0
import AutoUpdateChecker 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0
import NativeChrome 1.0

ApplicationWindow {
    property bool pollingActive: false

    // Set by SettingsView to force the back operation to pop all
    // pages except the initial view. This is required when doing
    // a retranslate() because AppView breaks for some reason.
    property bool clearOnBack: false

    // Set while a stream is starting or a game is quitting. Hides the toolbar
    // (the QML one, or the native one's items on macOS).
    property bool chromeHidden: false

    // The Settings section shown on macOS, kept while the app runs
    property string settingsSection: "video"

    // macOS: the Settings page, made in the background after launch and reused, so
    // opening Settings doesn't wait for it to be created. StackView leaves pages it was
    // handed alive when they're popped.
    property Item macSettingsPage: null
    property var macSettingsIncubator: null

    function macPrepareSettings() {
        var component = Qt.createComponent("qrc:/gui/SettingsView.qml")
        macSettingsIncubator = component.incubateObject(stackView, { "visible": false })
    }

    // The prepared page; if the background work hasn't finished yet (it runs in the
    // window's idle time), finish it now
    function macTakeSettingsPage() {
        if (macSettingsPage === null && macSettingsIncubator !== null) {
            if (macSettingsIncubator.status === Component.Loading) {
                macSettingsIncubator.forceCompletion()
            }
            if (macSettingsIncubator.status === Component.Ready) {
                macSettingsPage = macSettingsIncubator.object
            }
            macSettingsIncubator = null
        }
        return macSettingsPage
    }

    // How many NavigableDialogs are open (the macOS menu bar disables itself meanwhile)
    property int openDialogs: 0

    id: window
    // macOS starts as a compact list window, like other Mac launchers
    width: NativeChrome.enabled ? 400 : 1280
    height: NativeChrome.enabled ? 452 : 600
    minimumWidth: NativeChrome.enabled ? 340 : 0
    minimumHeight: NativeChrome.enabled ? 280 : 0

    // On macOS the window sits on a Liquid Glass backdrop drawn by NativeChrome
    color: NativeChrome.enabled ? "transparent" : Mat.Material.background

    // This function runs prior to creation of the initial StackView item
    function doEarlyInit() {
        // Override the background color to Material 2 colors for Qt 6.5+
        // in order to improve contrast between GFE's placeholder box art
        // and the background of the app grid.
        if (SystemProperties.usesMaterial3Theme) {
            Mat.Material.background = "#303030"
        }

        SdlGamepadKeyNavigation.enable()
    }

    Component.onCompleted: {
        // Show the window according to the user's preferences
        if (SystemProperties.hasDesktopEnvironment) {
            if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_MAXIMIZED) {
                window.showMaximized()
            }
            else if (StreamingPreferences.uiDisplayMode == StreamingPreferences.UI_FULLSCREEN) {
                window.showFullScreen()
            }
            else {
                window.show()
            }
        } else {
            window.showFullScreen()
        }

        // Replace our toolbar with the native one where the platform has it,
        // and give macOS a real menu bar with every action in it
        if (NativeChrome.enabled) {
            NativeChrome.attach(window)
            var menuBarComponent = Qt.createComponent("MacMenuBar.qml")
            if (menuBarComponent.status === Component.Ready) {
                window.menuBar = menuBarComponent.createObject(window)
                // Make the Settings page once the window is up
                Qt.callLater(macPrepareSettings)
            }
            else {
                console.error(menuBarComponent.errorString())
            }
        }

        // Display any modal dialogs for configuration warnings
        if (runConfigChecks) {
            if (SystemProperties.isWow64) {
                wow64Dialog.open()
            }

            // Hardware acceleration and unmapped gamepads are checked asynchronously
            SystemProperties.hasHardwareAccelerationChanged.connect(hasHardwareAccelerationChanged)
            SystemProperties.unmappedGamepadsChanged.connect(hasUnmappedGamepadsChanged)
            SystemProperties.startAsyncLoad()
        }
    }

    function hasHardwareAccelerationChanged() {
        if (!SystemProperties.hasHardwareAcceleration && StreamingPreferences.videoDecoderSelection !== StreamingPreferences.VDS_FORCE_SOFTWARE) {
            if (SystemProperties.isRunningXWayland) {
                xWaylandDialog.open()
            }
            else {
                noHwDecoderDialog.open()
            }
        }
    }

    function hasUnmappedGamepadsChanged() {
        if (SystemProperties.unmappedGamepads) {
            unmappedGamepadDialog.unmappedGamepads = SystemProperties.unmappedGamepads
            unmappedGamepadDialog.open()
        }
    }

    // It would be better to use TextMetrics here, but it always lays out
    // the text slightly more compactly than real Text does in ToolTip,
    // causing unexpected line breaks to be inserted
    Text {
        id: tooltipTextLayoutHelper
        visible: false
        font: ToolTip.toolTip.font
        text: ToolTip.toolTip.text
    }

    // The native macOS style has no tooltip of its own and falls back to Fusion's.
    // Draw it like the system's: small text on a rounded, bordered panel.
    Component {
        id: macToolTipBackground
        Rectangle {
            radius: 6
            color: window.palette.window
            border.width: 1
            border.color: Qt.rgba(window.palette.text.r, window.palette.text.g, window.palette.text.b, 0.15)
        }
    }

    // macOS: opening or leaving Settings resizes the window. Fade the page out, swap it
    // and resize while nothing is showing, then fade the new page in, instead of
    // sliding a page in and resizing it on screen.
    SequentialAnimation {
        id: macPageSwap
        property var swap

        NumberAnimation { target: stackView; property: "opacity"; to: 0; duration: 70; easing.type: Easing.InQuad }
        ScriptAction { script: macPageSwap.swap() }
        NumberAnimation { target: stackView; property: "opacity"; to: 1; duration: 120; easing.type: Easing.OutQuad }
    }

    function macSwapPages(swap) {
        if (macPageSwap.running) {
            return
        }
        macPageSwap.swap = swap
        macPageSwap.start()
    }

    function goBack() {
        if (NativeChrome.enabled && stackView.currentItem instanceof SettingsView) {
            macSwapPages(function() {
                if (clearOnBack) {
                    stackView.pop(null, StackView.Immediate)
                    clearOnBack = false
                }
                else {
                    stackView.pop(stackView.get(stackView.depth - 2), StackView.Immediate)
                }
            })
            return
        }

        if (clearOnBack) {
            // Pop all items except the first one
            stackView.pop(null)
            clearOnBack = false
        }
        else {
            stackView.pop()
        }
    }

    StackView {
        id: stackView
        anchors.fill: parent
        focus: true

        // This configures the maximum width of the singleton attached QML ToolTip. If left unconstrained,
        // it will never insert a line break and just extend on forever. (It has to be attached to an
        // Item; on the window it was ignored.)
        ToolTip.toolTip.contentWidth: Math.min(tooltipTextLayoutHelper.width, 400)

        Component.onCompleted: {
            // The shared tooltip can only be reached from an Item, so it's styled here
            if (NativeChrome.enabled) {
                ToolTip.toolTip.background = macToolTipBackground.createObject(ToolTip.toolTip)
                ToolTip.toolTip.font.pixelSize = 12
                ToolTip.toolTip.palette.toolTipText = Qt.binding(function() { return window.palette.windowText })
            }

            // Perform our early initialization before constructing
            // the initial view and pushing it to the StackView
            doEarlyInit()
            push(initialView)
        }

        onCurrentItemChanged: {
            // Ensure focus travels to the next view when going back
            if (currentItem) {
                currentItem.forceActiveFocus()
            }
        }

        Keys.onEscapePressed: {
            if (depth > 1) {
                goBack()
            }
            else if (!NativeChrome.enabled) {
                // Mac apps don't ask to quit on Escape; ⌘Q quits
                quitConfirmationDialog.open()
            }
        }

        Keys.onBackPressed: {
            if (depth > 1) {
                goBack()
            }
            else {
                quitConfirmationDialog.open()
            }
        }

        Keys.onMenuPressed: {
            settingsButton.clicked()
        }

        // This is a keypress we've reserved for letting the
        // SdlGamepadKeyNavigation object tell us to show settings
        // when Menu is consumed by a focused control.
        Keys.onHangupPressed: {
            settingsButton.clicked()
        }
    }

    // This timer keeps us polling for 5 minutes of inactivity
    // to allow the user to work with Moonlight on a second display
    // while dealing with configuration issues. This will ensure
    // machines come online even if the input focus isn't on Moonlight.
    Timer {
        id: inactivityTimer
        interval: 5 * 60000
        onTriggered: {
            if (!active && pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
    }

    onVisibleChanged: {
        // When we become invisible while streaming is going on,
        // stop polling immediately.
        if (!visible) {
            inactivityTimer.stop()

            if (pollingActive) {
                ComputerManager.stopPollingAsync()
                pollingActive = false
            }
        }
        else if (active) {
            // When we become visible and active again, start polling
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    onActiveChanged: {
        if (active) {
            // Stop the inactivity timer
            inactivityTimer.stop()

            // Restart polling if it was stopped
            if (!pollingActive) {
                ComputerManager.startPolling()
                pollingActive = true
            }
        }
        else {
            // Start the inactivity timer to stop polling
            // if focus does not return within a few minutes.
            inactivityTimer.restart()
        }

        // Poll for gamepad input only when the window is in focus
        SdlGamepadKeyNavigation.notifyWindowFocus(visible && active)
    }

    // Back to the computer list (Go > Computers)
    function goHome() {
        if (NativeChrome.enabled && stackView.currentItem instanceof SettingsView) {
            macSwapPages(function() {
                stackView.pop(null, StackView.Immediate)
                clearOnBack = false
            })
            return
        }

        stackView.pop(null)
        clearOnBack = false
    }

    function navigateTo(url, objectType)
    {
        var existingItem = stackView.find(function(item, index) {
            return item instanceof objectType
        })

        if (NativeChrome.enabled && objectType === SettingsView && existingItem === null) {
            macSwapPages(function() {
                // The page made ahead of time, if it's ready (creating it takes ~150 ms)
                if (macTakeSettingsPage() !== null) {
                    stackView.push(macSettingsPage, {}, StackView.Immediate)
                }
                else {
                    stackView.push(url, {}, StackView.Immediate)
                }
            })
            return
        }

        if (existingItem !== null) {
            // Pop to the existing item
            stackView.pop(existingItem)
        }
        else {
            // Create a new item
            stackView.push(url)
        }
    }

    // Native toolbar state and actions (macOS). These mirror the QML toolbar below.
    Binding { target: window; property: "title"; value: stackView.currentItem ? stackView.currentItem.objectName : ""; when: NativeChrome.enabled }
    Binding { target: NativeChrome; property: "canGoBack"; value: stackView.depth > 1 && !chromeHidden; when: NativeChrome.enabled }
    Binding { target: NativeChrome; property: "showAddPc"; value: stackView.currentItem instanceof PcView && !chromeHidden; when: NativeChrome.enabled }
    Binding { target: NativeChrome; property: "showHelp"; value: SystemProperties.hasBrowser && !chromeHidden; when: NativeChrome.enabled }
    Binding { target: NativeChrome; property: "showSettings"; value: !chromeHidden; when: NativeChrome.enabled }
    Binding { target: NativeChrome; property: "settingsOpen"; value: stackView.currentItem instanceof SettingsView; when: NativeChrome.enabled }
    Binding { target: NativeChrome; property: "updateText"; value: updateButton.visible ? updateButton.ToolTip.text : ""; when: NativeChrome.enabled }

    Connections {
        target: NativeChrome
        function onBackClicked() { goBack() }
        function onAddPcClicked() { addPcButton.clicked() }
        function onHelpClicked() { helpButton.clicked() }
        function onSettingsClicked() {
            // The gear toggles Settings
            if (stackView.currentItem instanceof SettingsView) {
                goBack()
            }
            else {
                settingsButton.clicked()
            }
        }
        function onUpdateClicked() { updateButton.clicked() }
    }

    header: ToolBar {
        id: toolBar
        visible: !NativeChrome.enabled && !chromeHidden
        height: visible ? 60 : 0
        anchors.topMargin: 5
        anchors.bottomMargin: 5

        Label {
            id: titleLabel
            visible: toolBar.width > 700
            anchors.fill: parent
            text: stackView.currentItem.objectName
            font.pointSize: 20
            elide: Label.ElideRight
            horizontalAlignment: Qt.AlignHCenter
            verticalAlignment: Qt.AlignVCenter
        }

        RowLayout {
            spacing: 10
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.fill: parent

            NavigableToolButton {
                // Only make the button visible if the user has navigated somewhere.
                visible: stackView.depth > 1

                iconSource: "qrc:/res/arrow_left.svg"

                onClicked: goBack()

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            // This label will appear when the window gets too small and
            // we need to ensure the toolbar controls don't collide
            Label {
                id: titleRowLabel
                font.pointSize: titleLabel.font.pointSize
                elide: Label.ElideRight
                horizontalAlignment: Qt.AlignHCenter
                verticalAlignment: Qt.AlignVCenter
                Layout.fillWidth: true

                // We need this label to always be visible so it can occupy
                // the remaining space in the RowLayout. To "hide" it, we
                // just set the text to empty string.
                text: !titleLabel.visible ? stackView.currentItem.objectName : ""
            }

            Label {
                id: versionLabel
                visible: stackView.currentItem instanceof SettingsView
                text: (Qt.platform.os === "osx" ? qsTr("Artemis %1") : qsTr("Version %1")).arg(SystemProperties.versionString)
                font.pointSize: 12
                horizontalAlignment: Qt.AlignRight
                verticalAlignment: Qt.AlignVCenter
            }

            NavigableToolButton {
                id: discordButton
                visible: SystemProperties.hasBrowser &&
                         stackView.currentItem instanceof SettingsView

                iconSource: "qrc:/res/discord.svg"

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Join our community on Discord")

                // TODO need to make sure browser is brought to foreground.
                onClicked: Qt.openUrlExternally("https://moonlight-stream.org/discord");

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                id: addPcButton
                visible: stackView.currentItem instanceof PcView

                iconSource:  "qrc:/res/ic_add_to_queue_white_48px.svg"

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Add PC manually") + (newPcShortcut.nativeText ? (" ("+newPcShortcut.nativeText+")") : "")

                Shortcut {
                    id: newPcShortcut
                    // The macOS menu bar owns this shortcut
                    enabled: !NativeChrome.enabled
                    sequence: StandardKey.New
                    onActivated: addPcButton.clicked()
                }

                onClicked: {
                    addPcDialog.open()
                }

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                property string browserUrl: ""

                id: updateButton

                iconSource: "qrc:/res/update.svg"

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered || visible

                // Invisible until we get a callback notifying us that
                // an update is available
                visible: false

                onClicked: {
                    if (SystemProperties.hasBrowser) {
                        Qt.openUrlExternally(browserUrl);
                    }
                }

                function updateAvailable(version, url)
                {
                    ToolTip.text = qsTr("Update available for Moonlight: Version %1").arg(version)
                    updateButton.browserUrl = url
                    updateButton.visible = true
                }

                Component.onCompleted: {
                    AutoUpdateChecker.onUpdateAvailable.connect(updateAvailable)
                    AutoUpdateChecker.start()
                }

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                id: helpButton
                visible: SystemProperties.hasBrowser

                iconSource: "qrc:/res/question_mark.svg"

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Help") + (helpShortcut.nativeText ? (" ("+helpShortcut.nativeText+")") : "")

                Shortcut {
                    id: helpShortcut
                    // The macOS menu bar owns this shortcut
                    enabled: !NativeChrome.enabled
                    sequence: StandardKey.HelpContents
                    onActivated: helpButton.clicked()
                }

                // TODO need to make sure browser is brought to foreground.
                onClicked: Qt.openUrlExternally("https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide");

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                // TODO: Implement gamepad mapping then unhide this button
                visible: false

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Gamepad Mapper")

                iconSource: "qrc:/res/ic_videogame_asset_white_48px.svg"

                onClicked: navigateTo("qrc:/gui/GamepadMapper.qml", GamepadMapper)

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }
            }

            NavigableToolButton {
                id: settingsButton

                iconSource:  "qrc:/res/settings.svg"

                onClicked: navigateTo("qrc:/gui/SettingsView.qml", SettingsView)

                Keys.onDownPressed: {
                    stackView.currentItem.forceActiveFocus(Qt.TabFocus)
                }

                Shortcut {
                    id: settingsShortcut
                    // The macOS menu bar owns this shortcut
                    enabled: !NativeChrome.enabled
                    sequence: StandardKey.Preferences
                    onActivated: settingsButton.clicked()
                }

                ToolTip.delay: 1000
                ToolTip.timeout: 3000
                ToolTip.visible: hovered
                ToolTip.text: qsTr("Settings") + (settingsShortcut.nativeText ? (" ("+settingsShortcut.nativeText+")") : "")
            }
        }
    }

    ErrorMessageDialog {
        id: noHwDecoderDialog
        text: qsTr("No functioning hardware accelerated video decoder was detected by Moonlight. " +
                   "Your streaming performance may be severely degraded in this configuration.")
        helpText: qsTr("Click the Help button for more information on solving this problem.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    ErrorMessageDialog {
        id: xWaylandDialog
        text: qsTr("Hardware acceleration doesn't work on XWayland. Continuing on XWayland may result in poor streaming performance. " +
                   "Try running with QT_QPA_PLATFORM=wayland or switch to X11.")
        helpText: qsTr("Click the Help button for more information.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Fixing-Hardware-Decoding-Problems"
    }

    NavigableMessageDialog {
        id: wow64Dialog
        standardButtons: Dialog.Ok | Dialog.Cancel
        text: qsTr("This version of Moonlight isn't optimized for your PC. Please download the '%1' version of Moonlight for the best streaming performance.").arg(SystemProperties.friendlyNativeArchName)
        onAccepted: {
            Qt.openUrlExternally("https://github.com/moonlight-stream/moonlight-qt/releases");
        }
    }

    ErrorMessageDialog {
        id: unmappedGamepadDialog
        property string unmappedGamepads : ""
        text: qsTr("Moonlight detected gamepads without a mapping:") + "\n" + unmappedGamepads
        helpTextSeparator: "\n\n"
        helpText: qsTr("Click the Help button for information on how to map your gamepads.")
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Gamepad-Mapping"
    }

    // This dialog appears when quitting via keyboard or gamepad button
    NavigableMessageDialog {
        id: quitConfirmationDialog
        standardButtons: Dialog.Yes | Dialog.No
        text: qsTr("Are you sure you want to quit?")
        // For keyboard/gamepad navigation
        onAccepted: Qt.quit()
    }

    // HACK: This belongs in StreamSegue but keeping a dialog around after the parent
    // dies can trigger bugs in Qt 5.12 that cause the app to crash. For now, we will
    // host this dialog in a QML component that is never destroyed.
    //
    // To repro: Start a stream, cut the network connection to trigger the "Connection
    // terminated" dialog, wait until the app grid times out back to the PC grid, then
    // try to dismiss the dialog.
    ErrorMessageDialog {
        id: streamSegueErrorDialog

        property bool quitAfter: false

        onClosed: {
            if (quitAfter) {
                Qt.quit()
            }

            // StreamSegue assumes its dialog will be re-created each time we
            // start streaming, so fake it by wiping out the text each time.
            text = ""
        }
    }

    NavigableDialog {
        id: addPcDialog
        property string label: NativeChrome.enabled ? qsTr("Add a computer by its IP address or hostname:")
                                                    : qsTr("Enter the IP address of your host PC:")

        standardButtons: Dialog.Ok | Dialog.Cancel

        onAboutToShow: {
            if (NativeChrome.enabled && footer.standardButton(Dialog.Ok)) {
                footer.standardButton(Dialog.Ok).text = qsTr("Add")
            }
        }

        onOpened: {
            // Force keyboard focus on the textbox so keyboard navigation works
            editText.forceActiveFocus()
        }

        onClosed: {
            editText.clear()
        }

        onAccepted: {
            if (editText.text) {
                ComputerManager.addNewHostManually(editText.text.trim())
            }
        }

        ColumnLayout {
            Label {
                text: addPcDialog.label
                font.bold: true
                wrapMode: Text.Wrap
                Layout.maximumWidth: NativeChrome.enabled ? 300 : Number.POSITIVE_INFINITY
            }

            TextField {
                id: editText
                Layout.fillWidth: true
                Layout.minimumWidth: NativeChrome.enabled ? 260 : 0
                placeholderText: NativeChrome.enabled ? "192.168.1.20" : ""
                focus: true

                Keys.onReturnPressed: {
                    addPcDialog.accept()
                }

                Keys.onEnterPressed: {
                    addPcDialog.accept()
                }
            }
        }
    }
}
