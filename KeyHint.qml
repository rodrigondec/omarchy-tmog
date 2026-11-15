import QtQuick
import qs.Commons
import qs.Ui

// A keyboard shortcut hint: the key drawn as a keycap, then what it does.
// Clicking it triggers the same action as pressing the key.
Item {
  id: hint

  property string keyName: ""
  property string label: ""
  property color textColor: Color.popups.text
  property string fontFamily: Style.font.family
  signal activated()

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    spacing: Style.space(6)

    Rectangle {
      id: cap
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(height, keyText.implicitWidth + Style.space(10))
      height: keyText.implicitHeight + Style.space(6)
      radius: Style.space(4)
      color: area.containsMouse ? Util.alpha(hint.textColor, 0.28) : Util.alpha(hint.textColor, 0.14)
      border.width: 1
      border.color: Util.alpha(hint.textColor, 0.55)

      Text {
        id: keyText
        anchors.centerIn: parent
        text: hint.keyName.toUpperCase()
        textFormat: Text.PlainText
        color: hint.textColor
        font.family: hint.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: hint.label
      textFormat: Text.PlainText
      color: Util.alpha(hint.textColor, 0.75)
      font.family: hint.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: hint.activated()
  }
}
