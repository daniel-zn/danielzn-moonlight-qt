import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Window 2.2

import ComputerModel 1.0

import ComputerManager 1.0
import StreamingPreferences 1.0
import SystemProperties 1.0
import SdlGamepadKeyNavigation 1.0
import NativeChrome 1.0

CenteredGridView {
    property ComputerModel computerModel : createModel()

    id: pcGrid
    focus: true
    activeFocusOnTab: true
    topMargin: NativeChrome.enabled ? 10 : 20
    bottomMargin: 5
    // macOS shows a list: one full-width row per PC
    cellWidth: NativeChrome.enabled ? Math.min(width - 20, 640) : 310
    cellHeight: NativeChrome.enabled ? 54 : 330
    objectName: qsTr("Computers")

    Component.onCompleted: {
        // Don't show any highlighted item until interacting with them.
        // We do this here instead of onActivated to avoid losing the user's
        // selection when backing out of a different page of the app.
        currentIndex = -1
    }

    // Note: Any initialization done here that is critical for streaming must
    // also be done in CliStartStreamSegue.qml, since this code does not run
    // for command-line initiated streams.
    StackView.onActivated: {
        // Setup signals on CM
        ComputerManager.computerAddCompleted.connect(addComplete)

        // Highlight the first item if a gamepad is connected
        if (currentIndex === -1 && SdlGamepadKeyNavigation.getConnectedGamepads() > 0) {
            currentIndex = 0
        }
    }

    StackView.onDeactivating: {
        ComputerManager.computerAddCompleted.disconnect(addComplete)
    }

    function pairingComplete(error)
    {
        // Close the PIN dialog
        pairDialog.close()

        // Display a failed dialog if we got an error
        if (error !== undefined) {
            errorDialog.text = error
            errorDialog.helpText = ""
            errorDialog.open()
        }
    }

    function addComplete(success, detectedPortBlocking)
    {
        if (!success) {
            errorDialog.text = qsTr("Unable to connect to the specified PC.")

            if (detectedPortBlocking) {
                errorDialog.text += "\n\n" + qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network.")
            }
            else {
                errorDialog.helpText = qsTr("Click the Help button for possible solutions.")
            }

            errorDialog.open()
        }
    }

    function createModel()
    {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', parent, '')
        model.initialize(ComputerManager)
        model.pairingCompleted.connect(pairingComplete)
        model.connectionTestCompleted.connect(testConnectionDialog.connectionTestComplete)
        return model
    }

    // macOS: a centered empty state that wraps within the compact window
    Column {
        anchors.centerIn: parent
        width: Math.min(pcGrid.width - 48, 300)
        spacing: 8
        visible: NativeChrome.enabled && pcGrid.count === 0

        Image {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 44; height: 44
            sourceSize { width: 44; height: 44 }
            source: NativeChrome.enabled ? NativeChrome.symbol("desktopcomputer", window.palette.text) : ""
            opacity: 0.45
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6

            ActivitySpinner {
                width: 14; height: 14
                anchors.verticalCenter: parent.verticalCenter
                visible: StreamingPreferences.enableMdns
                running: visible && pcGrid.count === 0
            }
            Label {
                text: StreamingPreferences.enableMdns ? qsTr("Looking for computers…") : qsTr("No computers")
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }

        Label {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            opacity: 0.65
            font.pixelSize: 11
            lineHeight: 1.2
            text: StreamingPreferences.enableMdns ?
                      qsTr("Moonlight finds PCs running Apollo or Sunshine on your network. You can also add one with the + button.") :
                      qsTr("Automatic PC discovery is off. Add your PC with the + button.")
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 5
        visible: !NativeChrome.enabled && pcGrid.count === 0

        ActivitySpinner {
            id: searchSpinner
            visible: StreamingPreferences.enableMdns
            running: visible
        }

        Label {
            height: searchSpinner.height
            elide: Label.ElideRight
            text: StreamingPreferences.enableMdns ? qsTr("Searching for compatible hosts on your local network...")
                                                  : qsTr("Automatic PC discovery is disabled. Add your PC manually.")
            font.pointSize: 20
            verticalAlignment: Text.AlignVCenter
            wrapMode: Text.Wrap
        }
    }

    model: computerModel

    delegate: NavigableItemDelegate {
        id: pcTile
        width: NativeChrome.enabled ? pcGrid.cellWidth : 300
        height: NativeChrome.enabled ? 50 : 320
        grid: pcGrid

        property alias pcContextMenu : pcContextMenuLoader.item

        // Read by the macOS menu bar, which acts on the selected computer
        readonly property string pcName: model.name
        readonly property bool pcOnline: model.online
        readonly property bool pcPaired: model.paired
        readonly property bool pcWakeable: model.wakeable
        readonly property bool pcStatusUnknown: model.statusUnknown

        // Set after a wake request until the PC comes online or we give up
        property bool waking: false

        Timer {
            id: wakingTimer
            interval: 90000
            onTriggered: pcTile.waking = false
        }

        onPcOnlineChanged: {
            if (pcOnline) {
                waking = false
            }
        }

        // Does what the PC is ready for: open its apps, pair it, or wake it
        function activate() {
            if (model.statusUnknown) {
                // Checking an asleep PC can take a while. Waking it is harmless if
                // it turns out to be awake, so don't make the user wait to wake it.
                if (!NativeChrome.enabled) {
                    // Using open() here because it may be activated by keyboard
                    pcContextMenu.open()
                }
                else if (model.wakeable) {
                    wake()
                }
                return
            }
            else if (model.online) {
                if (model.paired || !model.serverSupported) {
                    showApps(false)
                }
                else {
                    pair()
                }
            }
            else if (NativeChrome.enabled) {
                wake()
            }
            else {
                // Using open() here because it may be activated by keyboard
                pcContextMenu.open()
            }
        }

        function showApps(includeHidden) {
            if (!model.serverSupported) {
                errorDialog.text = qsTr("The version of GeForce Experience on %1 is not supported by this build of Moonlight. You must update Moonlight to stream from %1.").arg(model.name)
                errorDialog.helpText = ""
                errorDialog.open()
                return
            }

            var component = Qt.createComponent("AppView.qml")
            var properties = {"computerIndex": index, "objectName": model.name}
            if (includeHidden) {
                properties.showHiddenGames = true
            }
            stackView.push(component.createObject(stackView, properties))
        }

        function pair() {
            var pin = computerModel.generatePinString()

            // Kick off pairing in the background
            computerModel.pairComputer(index, pin)

            // Display the pairing dialog
            pairDialog.pin = pin
            pairDialog.open()
        }

        function wake() {
            if (!model.wakeable) {
                errorDialog.text = qsTr("%1 is offline, and Moonlight can't wake it because it doesn't know the PC's network address yet. Turn the PC on and pair with it, and Moonlight will be able to wake it next time.").arg(model.name)
                errorDialog.helpText = ""
                errorDialog.open()
                return
            }
            computerModel.wakeComputer(index)
            waking = true
            wakingTimer.restart()
        }

        function rename() {
            renamePcDialog.pcIndex = index
            renamePcDialog.originalName = model.name
            renamePcDialog.open()
        }

        function remove() {
            deletePcDialog.pcIndex = index
            deletePcDialog.pcName = model.name
            deletePcDialog.open()
        }

        function testNetwork() {
            computerModel.testConnectionForComputer(index)
            testConnectionDialog.open()
        }

        function showDetails() {
            showPcDetailsDialog.pcDetails = model.details
            showPcDetailsDialog.open()
        }

        // macOS: a list row (computer symbol, name, status), like a Finder sidebar
        // or System Settings list. Other platforms keep the Material tile below.
        Component.onCompleted: {
            if (NativeChrome.enabled) {
                background = macRowBackgroundComponent.createObject(pcTile)
            }
        }

        Component {
            id: macRowBackgroundComponent
            Rectangle {
                radius: 10
                color: pcTile.highlighted ? pcTile.palette.highlight
                     : pcTile.down ? Qt.rgba(pcTile.palette.text.r, pcTile.palette.text.g, pcTile.palette.text.b, 0.14)
                     : pcTile.hovered ? Qt.rgba(pcTile.palette.text.r, pcTile.palette.text.g, pcTile.palette.text.b, 0.08)
                     : "transparent"
                Behavior on color { ColorAnimation { duration: 100 } }
            }
        }

        Item {
            id: macRow
            visible: NativeChrome.enabled
            anchors.fill: parent

            // White on the accent color; in an inactive window the selection turns
            // gray, so the text stays dark there, as in Finder
            readonly property color textColor: pcTile.highlighted && pcTile.Window.active ? "white" : pcTile.palette.text

            Image {
                id: macPcIcon
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 30; height: 30
                sourceSize { width: 30; height: 30 }
                source: NativeChrome.enabled ? NativeChrome.symbol("desktopcomputer", macRow.textColor) : ""
                opacity: model.online ? 1.0 : 0.5
            }

            Column {
                anchors.left: macPcIcon.right
                anchors.leftMargin: 12
                anchors.right: macStatusIcon.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Label {
                    width: parent.width
                    text: model.name
                    color: macRow.textColor
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Label {
                    width: parent.width
                    text: !model.online && pcTile.waking ? qsTr("Waking up…")
                        : model.statusUnknown ? qsTr("Connecting…")
                        : !model.online && model.wakeable ? qsTr("Offline · Double-click to wake")
                        : !model.online ? qsTr("Offline")
                        : !model.paired ? qsTr("Not paired · Double-click to pair")
                        : qsTr("Online")
                    color: macRow.textColor
                    opacity: 0.65
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }

            // Status on the right: spinner while checking, then a symbol
            ActivitySpinner {
                anchors.centerIn: macStatusIcon
                width: 20; height: 20
                visible: model.statusUnknown || (pcTile.waking && !model.online)
                running: visible
            }
            Image {
                id: macStatusIcon
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18
                sourceSize { width: 18; height: 18 }
                visible: !model.statusUnknown && !(pcTile.waking && !model.online)
                source: !NativeChrome.enabled ? ""
                      : !model.online ? NativeChrome.symbol("moon.zzz.fill", macRow.textColor)
                      : !model.paired ? NativeChrome.symbol("lock.fill", macRow.textColor)
                      : NativeChrome.symbol("chevron.right", macRow.textColor)
                opacity: model.online && !model.paired ? 1.0 : 0.5
            }
        }

        Image {
            id: pcIcon
            visible: !NativeChrome.enabled
            anchors.horizontalCenter: parent.horizontalCenter
            source: "qrc:/res/desktop_windows-48px.svg"
            sourceSize {
                width: 200
                height: 200
            }
        }

        Image {
            // TODO: Tooltip
            id: stateIcon
            anchors.horizontalCenter: pcIcon.horizontalCenter
            anchors.verticalCenter: pcIcon.verticalCenter
            anchors.verticalCenterOffset: !model.online ? -18 : -16
            visible: !NativeChrome.enabled && !model.statusUnknown && (!model.online || !model.paired)
            source: !model.online ? "qrc:/res/warning_FILL1_wght300_GRAD200_opsz24.svg" : "qrc:/res/baseline-lock-24px.svg"
            sourceSize {
                width: !model.online ? 75 : 70
                height: !model.online ? 75 : 70
            }
        }

        ActivitySpinner {
            id: statusUnknownSpinner
            anchors.horizontalCenter: pcIcon.horizontalCenter
            anchors.verticalCenter: pcIcon.verticalCenter
            anchors.verticalCenterOffset: -15
            width: 75
            height: 75
            visible: !NativeChrome.enabled && model.statusUnknown
            running: visible
        }

        Label {
            id: pcNameText
            visible: !NativeChrome.enabled
            text: model.name

            width: parent.width
            anchors.top: pcIcon.bottom
            anchors.bottom: parent.bottom
            font.pointSize: 36
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            elide: Text.ElideRight
        }

        Loader {
            id: pcContextMenuLoader
            asynchronous: true
            sourceComponent: NavigableMenu {
                id: pcContextMenu
                initiator: pcContextMenuLoader.parent
                MenuItem {
                    text: qsTr("PC Status: %1").arg(model.online ? qsTr("Online") : qsTr("Offline"))
                    font.bold: true
                    enabled: false
                    // macOS shows the status in the row itself
                    visible: !NativeChrome.enabled
                    height: visible ? implicitHeight : 0
                }
                NavigableMenuItem {
                    text: qsTr("Open")
                    onTriggered: pcTile.showApps(false)
                    visible: NativeChrome.enabled && model.online && model.paired
                }
                NavigableMenuItem {
                    text: qsTr("Pair…")
                    onTriggered: pcTile.pair()
                    visible: NativeChrome.enabled && model.online && !model.paired
                }
                // Other platforms keep upstream's order: View All Apps, Wake, Test Network,
                // Rename, Delete, View Details
                NavigableMenuItem {
                    text: NativeChrome.enabled ? qsTr("Show All Games, Including Hidden") : qsTr("View All Apps")
                    onTriggered: pcTile.showApps(true)
                    visible: model.online && model.paired
                }
                NavigableMenuItem {
                    text: qsTr("Wake PC")
                    onTriggered: pcTile.wake()
                    visible: !model.online && model.wakeable
                }
                MenuSeparator {
                    visible: NativeChrome.enabled
                    height: visible ? implicitHeight : 0
                }
                NavigableMenuItem {
                    text: NativeChrome.enabled ? qsTr("Test Network…") : qsTr("Test Network")
                    onTriggered: pcTile.testNetwork()
                }
                NavigableMenuItem {
                    text: NativeChrome.enabled ? qsTr("Rename…") : qsTr("Rename PC")
                    onTriggered: pcTile.rename()
                }
                NavigableMenuItem {
                    text: qsTr("Get Info")
                    onTriggered: pcTile.showDetails()
                    visible: NativeChrome.enabled
                }
                MenuSeparator {
                    visible: NativeChrome.enabled
                    height: visible ? implicitHeight : 0
                }
                NavigableMenuItem {
                    text: NativeChrome.enabled ? qsTr("Remove…") : qsTr("Delete PC")
                    onTriggered: pcTile.remove()
                }
                NavigableMenuItem {
                    text: qsTr("View Details")
                    onTriggered: pcTile.showDetails()
                    visible: !NativeChrome.enabled
                }
            }
        }

        // macOS works like a Finder list: a click selects, a double-click (or
        // Return) opens. Elsewhere a click opens, as it always has.
        onClicked: {
            if (NativeChrome.enabled) {
                pcGrid.currentIndex = index
                pcGrid.forceActiveFocus()
            }
            else {
                activate()
            }
        }

        onDoubleClicked: {
            if (NativeChrome.enabled) {
                activate()
            }
        }

        Keys.onReturnPressed: {
            if (NativeChrome.enabled) {
                activate()
            }
        }

        Keys.onEnterPressed: {
            if (NativeChrome.enabled) {
                activate()
            }
        }

        onPressAndHold: {
            if (NativeChrome.enabled) {
                // Right-clicking a row selects it, as in Finder
                pcGrid.currentIndex = index
                pcGrid.forceActiveFocus()
            }

            // popup() ensures the menu appears under the mouse cursor
            if (pcContextMenu.popup) {
                pcContextMenu.popup()
            }
            else {
                // Qt 5.9 doesn't have popup()
                pcContextMenu.open()
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton;
            onClicked: {
                parent.pressAndHold()
            }
        }

        Keys.onMenuPressed: {
            // We must use open() here so the menu is positioned on
            // the ItemDelegate and not where the mouse cursor is
            pcContextMenu.open()
        }

        Keys.onDeletePressed: {
            remove()
        }
    }

    ErrorMessageDialog {
        id: errorDialog

        // Using Setup-Guide here instead of Troubleshooting because it's likely that users
        // will arrive here by forgetting to enable GameStream or not forwarding ports.
        helpUrl: "https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide"
    }

    NavigableMessageDialog {
        id: pairDialog
        closePolicy: Popup.CloseOnEscape

        // don't allow edits to the rest of the window while open
        property string pin : "0000"
        // macOS: the PIN large on its own line, so it's easy to read while typing it
        text: NativeChrome.enabled ?
                  // (Qt Quick labels take StyledText, a small HTML subset without CSS)
                  qsTr("Enter this PIN on your host PC:") + "<br><font size=\"6\"><b>" + pin + "</b></font><br>" +
                  qsTr("With Apollo or Sunshine, enter it on the PIN page of the host's web UI. This closes by itself once you're paired.") :
                  qsTr("Please enter %1 on your host PC. This dialog will close when pairing is completed.").arg(pin)+"\n\n"+
                  qsTr("If your host PC is running Sunshine, navigate to the Sunshine web UI to enter the PIN.")
        imageSrc: NativeChrome.enabled ? "qrc:/res/baseline-lock-24px.svg" : ""
        standardButtons: Dialog.Cancel
        onRejected: {
            // FIXME: We should interrupt pairing here
        }
    }

    NavigableMessageDialog {
        id: deletePcDialog
        // don't allow edits to the rest of the window while open
        property int pcIndex : -1
        property string pcName : ""
        text: qsTr("Are you sure you want to remove '%1'?").arg(pcName)
        standardButtons: Dialog.Yes | Dialog.No
        acceptText: NativeChrome.enabled ? qsTr("Remove") : ""
        rejectText: NativeChrome.enabled ? qsTr("Cancel") : ""

        onAccepted: {
            computerModel.deleteComputer(pcIndex)
        }
    }

    NavigableMessageDialog {
        id: testConnectionDialog
        closePolicy: Popup.CloseOnEscape
        standardButtons: Dialog.Ok

        onAboutToShow: {
            testConnectionDialog.text = qsTr("Moonlight is testing your network connection to determine if any required ports are blocked.") + "\n\n" + qsTr("This may take a few seconds…")
            showSpinner = true
        }

        function connectionTestComplete(result, blockedPorts)
        {
            if (result === -1) {
                text = qsTr("The network test could not be performed because none of Moonlight's connection testing servers were reachable from this PC. Check your Internet connection or try again later.")
                imageSrc = "qrc:/res/baseline-warning-24px.svg"
            }
            else if (result === 0) {
                text = qsTr("This network does not appear to be blocking Moonlight. If you still have trouble connecting, check your PC's firewall settings.") + "\n\n" + qsTr("If you are trying to stream over the Internet, install the Moonlight Internet Hosting Tool on your gaming PC and run the included Internet Streaming Tester to check your gaming PC's Internet connection.")
                imageSrc = "qrc:/res/baseline-check_circle_outline-24px.svg"
            }
            else {
                text = qsTr("Your PC's current network connection seems to be blocking Moonlight. Streaming over the Internet may not work while connected to this network.") + "\n\n" + qsTr("The following network ports were blocked:") + "\n"
                text += blockedPorts
                imageSrc = "qrc:/res/baseline-error_outline-24px.svg"
            }

            // Stop showing the spinner and show the image instead
            showSpinner = false
        }
    }

    NavigableDialog {
        id: renamePcDialog
        property string label: qsTr("Enter the new name for this PC:")
        property string originalName
        property int pcIndex : -1;

        standardButtons: Dialog.Ok | Dialog.Cancel

        onAboutToShow: {
            if (NativeChrome.enabled && footer.standardButton(Dialog.Ok)) {
                footer.standardButton(Dialog.Ok).text = qsTr("Rename")
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
                computerModel.renameComputer(pcIndex, editText.text)
            }
        }

        ColumnLayout {
            Label {
                text: renamePcDialog.label
                font.bold: true
                wrapMode: Text.Wrap
                Layout.maximumWidth: NativeChrome.enabled ? 300 : Number.POSITIVE_INFINITY
            }

            TextField {
                id: editText
                placeholderText: renamePcDialog.originalName
                Layout.fillWidth: true
                Layout.minimumWidth: NativeChrome.enabled ? 260 : 0
                focus: true

                Keys.onReturnPressed: {
                    renamePcDialog.accept()
                }

                Keys.onEnterPressed: {
                    renamePcDialog.accept()
                }
            }
        }
    }

    NavigableMessageDialog {
        id: showPcDetailsDialog
        property string pcDetails : "";
        text: showPcDetailsDialog.pcDetails
        imageSrc: "qrc:/res/baseline-help_outline-24px.svg"
        standardButtons: Dialog.Ok
    }

    ScrollBar.vertical: ScrollBar {}
}
