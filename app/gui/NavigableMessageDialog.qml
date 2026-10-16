import QtQuick 2.0
import QtQuick.Controls 2.5
import QtQuick.Layouts 1.2

import NativeChrome 1.0

NavigableDialog {
    id: dialog

    property alias text: dialogLabel.dialogText
    property alias showSpinner: dialogSpinner.visible
    property string imageSrc

    // Optional button labels, so a dialog can say what it does ("Remove", "Quit Game")
    // instead of Yes/OK, as the macOS Human Interface Guidelines ask
    property string acceptText
    property string rejectText

    property string helpText
    property string helpUrl : "https://github.com/moonlight-stream/moonlight-docs/wiki/Troubleshooting"
    property string helpTextSeparator : " "

    onAboutToShow: {
        if (acceptText || rejectText) {
            var accept = dialogButtonBox.standardButton(Dialog.Yes) || dialogButtonBox.standardButton(Dialog.Ok)
            var reject = dialogButtonBox.standardButton(Dialog.No) || dialogButtonBox.standardButton(Dialog.Cancel)
            if (accept && acceptText) {
                accept.text = acceptText
            }
            if (reject && rejectText) {
                reject.text = rejectText
            }
        }
    }

    // SF Symbols stand in for the Material icons on macOS, which are drawn
    // white for a dark theme and disappear in light mode
    function macSymbol(src) {
        if (src.indexOf("check_circle") >= 0) {
            return NativeChrome.symbol("checkmark.circle.fill", "#30D158")
        }
        else if (src.indexOf("lock") >= 0) {
            return NativeChrome.symbol("lock.fill", "#0A84FF")
        }
        else if (src.indexOf("help") >= 0) {
            return NativeChrome.symbol("questionmark.circle.fill", "#0A84FF")
        }
        // The system's yellow caution triangle, as in macOS alerts
        return "image://sfsymbol/exclamationmark.triangle.fill/multicolor"
    }

    onOpened: {
        // Force keyboard focus on the label so keyboard navigation works
        if (dialogButtonBox.count > 0) {
            dialogButtonBox.itemAt(dialogButtonBox.count - 1).forceActiveFocus(Qt.TabFocus)
        }
    }

    RowLayout {
        spacing: NativeChrome.enabled ? 14 : 10

        ActivitySpinner {
            id: dialogSpinner
            visible: false
            running: visible
        }

        Image {
            id: dialogImage
            readonly property string materialSource: imageSrc ? imageSrc :
                        (standardButtons & Dialog.Yes) ?
                        "qrc:/res/baseline-help_outline-24px.svg" :
                        "qrc:/res/baseline-error_outline-24px.svg"
            source: NativeChrome.enabled ? macSymbol(materialSource) : materialSource
            Layout.alignment: NativeChrome.enabled ? Qt.AlignTop : Qt.AlignVCenter
            Layout.preferredWidth: NativeChrome.enabled ? 36 : -1
            Layout.preferredHeight: NativeChrome.enabled ? 36 : -1
            sourceSize {
                // The icon should be square so use the height as the width too
                width: NativeChrome.enabled ? 36 : 50
                height: NativeChrome.enabled ? 36 : 50
            }
            visible: !showSpinner
        }

        Label {
            property string dialogText

            id: dialogLabel
            text: dialogText + ((helpText && (standardButtons & Dialog.Help)) ? (helpTextSeparator + helpText) : "")
            wrapMode: Text.Wrap
            elide: Label.ElideRight
            lineHeight: NativeChrome.enabled ? 1.15 : 1.0

            // Cap the width so the dialog doesn't grow horizontally forever. This
            // will cause word wrap to kick in.
            // macOS: keep the dialog inside the compact window
            Layout.maximumWidth: NativeChrome.enabled && dialog.parent ? Math.min(360, dialog.parent.width - 120) : 400
            Layout.maximumHeight: 400
        }
    }

    footer: DialogButtonBox {
        id: dialogButtonBox
        objectName: "macButtonBox"
        standardButtons: dialog.standardButtons

        // macOS: bordered push buttons on the dialog's own background, with the
        // accepting button as the default (accent) button
        Component.onCompleted: {
            if (NativeChrome.enabled) {
                alignment = Qt.AlignRight
                // The style's own is a square panel that pokes out of the rounded dialog
                if (background) {
                    background.visible = false
                }
            }
        }

        delegate: Button {
            flat: !NativeChrome.enabled
            highlighted: NativeChrome.enabled &&
                         (DialogButtonBox.buttonRole === DialogButtonBox.AcceptRole ||
                          DialogButtonBox.buttonRole === DialogButtonBox.YesRole)

            Keys.onReturnPressed: clicked()
            Keys.onEnterPressed: clicked()
            Keys.onRightPressed: nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocus)
            Keys.onLeftPressed: nextItemInFocusChain(false).forceActiveFocus(Qt.TabFocus)
        }

        onHelpRequested: {
            Qt.openUrlExternally(helpUrl)
            close()
        }
    }
}
