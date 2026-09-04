const test = require("node:test")
const assert = require("node:assert")
const M = require("../YoutubeMusicModel.js")

const monitor = {
  name: "DP-5",
  x: 0,
  y: 0,
  width: 5120,
  height: 2880,
  scale: 2,
  reserved: [0, 26, 0, 0]
}

test("display mode defaults to icon", () => {
  assert.equal(M.normalizeDisplay(), "icon")
  assert.equal(M.normalizeDisplay("player"), "player")
  assert.equal(M.toggledDisplay("icon"), "player")
})

test("click actions", () => {
  assert.equal(M.clickAction("icon", "left"), "togglePanel")
  assert.equal(M.clickAction("player", "left"), "playPause")
  assert.equal(M.clickAction("icon", "middle"), "toggleDisplay")
})

test("parking special workspace names", () => {
  assert.ok(M.isParkingSpecial("wolften-youtube-music"))
  assert.ok(M.isParkingSpecial("special:wolften-youtube-music"))
  assert.ok(!M.isParkingSpecial(""))
  assert.ok(!M.isParkingSpecial("scratchpad"))
  assert.ok(!M.isParkingSpecial("special:scratchpad"))
})

test("window matching", () => {
  assert.ok(M.isMusicWindow({ class: "wolften.youtube-music" }))
  assert.ok(M.isMusicWindow({ class: "chrome-music.youtube.com__-Default" }))
  assert.ok(!M.isMusicWindow({ class: "chromium" }))
  assert.ok(!M.isMusicWindow({ class: "chrome-youtube.com__-Default" }))
  assert.ok(!M.isMusicWindow({ class: "google-chrome" }))
})

test("placement under a top bar", () => {
  const rect = M.placement({
    screenName: "DP-5",
    x: 200,
    y: 0,
    width: 28,
    height: 26,
    barPosition: "top"
  }, monitor, 1080, 760, 12)
  assert.ok(rect.width <= 2560)
  assert.ok(rect.height <= 1414)
  assert.ok(rect.y >= 26)
})

test("compact size ignores a fullscreen tiled window", () => {
  const work = M.monitorWorkArea(monitor)
  const size = M.compactSize([work.width, work.height], work)
  assert.equal(size.width, M.DROPDOWN_WIDTH)
  assert.equal(size.height, M.DROPDOWN_HEIGHT)
})

test("compact size keeps a reasonable dropdown", () => {
  const work = M.monitorWorkArea(monitor)
  const size = M.compactSize([900, 640], work)
  assert.equal(size.width, 900)
  assert.equal(size.height, 640)
})
