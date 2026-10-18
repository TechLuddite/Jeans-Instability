import QtQuick
import qs.Commons

// Every line of text in the panel is one of these. Plugin names come from
// other people's manifests, so they are never interpreted as markup.
Text {
  textFormat: Text.PlainText
  wrapMode: Text.Wrap
  font.family: Style.font.family
  font.pixelSize: Style.font.body
}
