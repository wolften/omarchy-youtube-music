import QtQuick
import QtQuick.Shapes
import qs.Commons

// YouTube Music mark: rounded square with a play-triangle cutout.
// Drawn as a single even-odd silhouette so it reads like the other
// Omarchy bar icons — one foreground color, no brand red.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: root.color
      strokeWidth: 0
      fillRule: ShapePath.OddEvenFill
      PathSvg { path: root.markPath }
    }
  }

  readonly property string markPath: {
    var s = Math.max(1, root.width)
    var inset = s * 0.06
    var x = inset
    var y = inset
    var w = s - inset * 2
    var h = w
    var r = w * 0.22
    var tx = x + w * 0.34
    var ty = y + h * 0.26
    var th = h * 0.48
    var tw = w * 0.42
    return roundedRect(x, y, w, h, r)
      + " M " + tx.toFixed(2) + "," + ty.toFixed(2)
      + " L " + tx.toFixed(2) + "," + (ty + th).toFixed(2)
      + " L " + (tx + tw).toFixed(2) + "," + (ty + th / 2).toFixed(2)
      + " Z"
  }

  function roundedRect(x, y, w, h, r) {
    return "M " + (x + r).toFixed(2) + "," + y.toFixed(2)
      + " H " + (x + w - r).toFixed(2)
      + " A " + r.toFixed(2) + "," + r.toFixed(2) + " 0 0 1 " + (x + w).toFixed(2) + "," + (y + r).toFixed(2)
      + " V " + (y + h - r).toFixed(2)
      + " A " + r.toFixed(2) + "," + r.toFixed(2) + " 0 0 1 " + (x + w - r).toFixed(2) + "," + (y + h).toFixed(2)
      + " H " + (x + r).toFixed(2)
      + " A " + r.toFixed(2) + "," + r.toFixed(2) + " 0 0 1 " + x.toFixed(2) + "," + (y + h - r).toFixed(2)
      + " V " + (y + r).toFixed(2)
      + " A " + r.toFixed(2) + "," + r.toFixed(2) + " 0 0 1 " + (x + r).toFixed(2) + "," + y.toFixed(2)
      + " Z"
  }
}
