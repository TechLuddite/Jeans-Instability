import QtQuick
import qs.Ui

// The bar icon and the panel that opens under it. The icon shows how many
// enabled plugins have a GitHub repository you have not starred.
BarWidget {
  id: root
  moduleName: "io.github.techluddite.jeans-instability"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property int unstarred: panelLoader.item ? Number(panelLoader.item.unstarredCount) || 0 : 0

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-star_outline U+F04D2, and nf-md-star U+F04CE once everything is starred.
    text: root.unstarred > 0
      ? String.fromCodePoint(0xF04D2) + " " + Math.min(root.unstarred, 999)
      : String.fromCodePoint(0xF04CE)
    tooltipText: root.unstarred > 0
      ? Math.min(root.unstarred, 999) + " plugin repositories not starred"
      : "Jeans Instability"
    active: root.opened
    onPressed: function (buttonCode) { if (buttonCode === Qt.LeftButton) root.toggle() }
  }
}
