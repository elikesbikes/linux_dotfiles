import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real vbW: 24
  readonly property real vbH: 24
  readonly property real markScale: Math.min(width / vbW, height / vbH)

  Shape {
    x: (root.width - root.vbW * root.markScale) / 2
    y: (root.height - root.vbH * root.markScale) / 2
    width: root.vbW
    height: root.vbH
    antialiasing: true
    preferredRendererType: Shape.CurveRenderer
    transform: Scale { xScale: root.markScale; yScale: root.markScale }

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      PathSvg {
        // Video camera icon (Material Design style)
        path: "M17 10.5V7c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h12c.55 0 1-.45 1-1v-3.5l4 4v-11l-4 4zM14 17H5V7h9v10z"
      }
    }
  }
}
