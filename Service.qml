import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.Commons
import "YoutubeMusicModel.js" as Model

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string sourceDir: manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
  readonly property string controlPath: sourceDir ? sourceDir + "/control.sh" : ""
  readonly property string rulesPath: sourceDir ? sourceDir + "/hypr/youtube-music.lua" : ""

  property string windowAddress: ""
  property int browserPid: 0
  property bool opened: false
  property bool launching: false
  property bool rulesInstalled: false
  property string ownerScreen: ""
  property var lastAnchor: null
  property var monitors: []
  property bool dismissArmed: false
  property bool themeFocusLost: false
  property bool themePickerOpen: false
  property string pendingFocusAddress: ""
  property double themeFocusUntil: 0
  property string lastError: ""
  property string initializedFor: ""

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var activePlayer: Model.playerForPid(players, browserPid)
  readonly property bool hasMedia: activePlayer !== null
    && !!(activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? String(activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? String(activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer ? String(activePlayer.trackAlbum || "") : ""
  readonly property string artUrl: activePlayer ? String(activePlayer.trackArtUrl || "") : ""
  readonly property bool playing: activePlayer ? activePlayer.isPlaying === true : false

  property string stateIntent: ""
  property var stateAnchor: null
  property string stateOutput: ""
  property string queuedIntent: ""
  property var queuedAnchor: null
  property bool syncQueued: false
  property string actionQueued: ""
  property var actionQueuedAnchor: null
  property int launchAttempts: 0
  property var launchAnchor: null
  property string actionKind: ""

  function protectThemeFocus(duration) {
    var milliseconds = Math.max(0, Number(duration || 2000))
    themeFocusUntil = Math.max(themeFocusUntil, Date.now() + milliseconds)
  }

  function themeFocusProtected() {
    return themePickerOpen || Date.now() < themeFocusUntil
  }

  function notifyFailure(message) {
    lastError = String(message || "YouTube Music could not be opened")
    Quickshell.execDetached(["omarchy-notification-send", "YouTube Music", lastError])
  }

  function requestState(intent, anchor) {
    var nextIntent = String(intent || "sync")
    if (stateProc.running) {
      if (nextIntent !== "sync") {
        queuedIntent = nextIntent
        queuedAnchor = anchor || lastAnchor
      } else {
        syncQueued = true
      }
      return
    }

    stateIntent = nextIntent
    stateAnchor = anchor || lastAnchor
    stateOutput = ""
    stateProc.command = [controlPath, "state"]
    stateProc.running = controlPath !== ""
  }

  function drainStateQueue() {
    if (queuedIntent !== "") {
      var intent = queuedIntent
      var anchor = queuedAnchor
      queuedIntent = ""
      queuedAnchor = null
      requestState(intent, anchor)
    } else if (syncQueued) {
      syncQueued = false
      requestState("sync", null)
    }
  }

  function syncState(state) {
    var client = state && state.client ? state.client : null
    monitors = state && Array.isArray(state.monitors) ? state.monitors : []
    windowAddress = client ? Model.normalizeAddress(client.address) : ""
    browserPid = client ? (parseInt(client.pid, 10) || 0) : 0
    if (client) lastError = ""
    var wasOpened = opened
    opened = !!(state && state.open && windowAddress)
    if (opened && !dismissArmed) dismissDelay.restart()
    if (opened && !wasOpened) setClickaway(true)
    if (!opened) {
      dismissArmed = false
      dismissDelay.stop()
      dismissFocusDelay.stop()
      themeRefocusDelay.stop()
      themeFocusLost = false
      themePickerOpen = false
      pendingFocusAddress = ""
      themeFocusUntil = 0
      if (wasOpened) setClickaway(false)
    }
    ownerScreen = opened && state && state.openScreen ? String(state.openScreen) : ""
  }

  function handleState(raw, intent, anchor) {
    var state
    try {
      state = JSON.parse(String(raw || "{}"))
    } catch (error) {
      if (intent !== "sync" && intent !== "awaitLaunch")
        notifyFailure("Could not read the Hyprland window state")
      return
    }

    syncState(state)

    if (intent === "toggle") {
      if (actionProc.running) {
        // A show/hide is still in flight: decide after it lands, from
        // fresh ground truth, instead of racing it.
        actionQueued = "toggle"
        actionQueuedAnchor = anchor || lastAnchor
      } else if (opened) hide()
      else if (state.client) showExisting(state.client, state.monitors, anchor)
      else launch(anchor)
    } else if (intent === "show") {
      if (actionProc.running) {
        actionQueued = "show"
        actionQueuedAnchor = anchor || lastAnchor
      } else if (state.client) showExisting(state.client, state.monitors, anchor)
      else launch(anchor)
    } else if (intent === "awaitLaunch") {
      if (state.client) {
        launchPoll.stop()
        launching = false
        showExisting(state.client, state.monitors, launchAnchor)
      }
    }
  }

  function launch(anchor) {
    if (!rulesInstalled) installRules(true)
    if (launching || launchProc.running) return
    launching = true
    lastError = ""
    launchAttempts = 0
    launchAnchor = anchor || lastAnchor
    launchProc.command = [controlPath, "launch"]
    launchProc.running = true
  }

  function showExisting(client, availableMonitors, anchor) {
    var actualAnchor = anchor || lastAnchor || ({
      screenName: "",
      x: 0,
      y: 0,
      width: 1,
      height: 1,
      barPosition: "top"
    })
    var monitor = Model.monitorFor(availableMonitors, actualAnchor.screenName)
    var size = Model.compactSize(client && client.size, Model.monitorWorkArea(monitor))
    var rect = Model.placement(actualAnchor, monitor, size.width, size.height, 12)
    var address = Model.normalizeAddress(client && client.address)
    if (!monitor || !rect || !address) {
      notifyFailure("Could not place the YouTube Music window")
      return
    }

    lastAnchor = actualAnchor
    windowAddress = address
    browserPid = parseInt(client.pid, 10) || 0
    ownerScreen = String(monitor.name || actualAnchor.screenName || "")
    dismissArmed = false
    actionKind = "show"
    actionProc.command = [
      controlPath, "show", address, ownerScreen,
      String(rect.x), String(rect.y), String(rect.width), String(rect.height)
    ]
    actionProc.running = true
  }

  function show(anchor) {
    if (!rulesInstalled) installRules(true)
    if (anchor) lastAnchor = anchor
    requestState("show", anchor || lastAnchor)
  }

  function hide() {
    if (!opened && !windowAddress) return
    if (actionProc.running) {
      actionQueued = "hide"
      actionQueuedAnchor = null
      return
    }
    dismissArmed = false
    dismissFocusDelay.stop()
    pendingFocusAddress = ""
    actionKind = "hide"
    actionProc.command = [controlPath, "hide", windowAddress]
    actionProc.running = true
  }

  // Click-away bind (global non-consuming LMB): armed only while the
  // dropdown is open so normal clicks are untouched otherwise.
  function setClickaway(armed) {
    if (!controlPath || clickawayProc.running) return
    clickawayProc.command = [controlPath, armed ? "clickaway-arm" : "clickaway-disarm"]
    clickawayProc.running = true
  }

  function dismissParkingOverlay() {
    if (!controlPath || dismissSpecialProc.running) return
    dismissSpecialProc.command = [controlPath, "dismiss-special"]
    dismissSpecialProc.running = true
  }

  function toggle(anchor) {
    if (anchor) lastAnchor = anchor
    requestState("toggle", anchor || lastAnchor)
  }

  function runAction(action) {
    var player = activePlayer
    if (!player) return false

    if (action === "next" && player.canGoNext) {
      player.next()
      return true
    }
    if (action === "previous" && player.canGoPrevious) {
      player.previous()
      return true
    }
    if (action === "playPause") {
      if (player.isPlaying && player.canPause) player.pause()
      else if (!player.isPlaying && player.canPlay) player.play()
      else if (player.canTogglePlaying) player.togglePlaying()
      else return false
      return true
    }
    return false
  }

  function installRules(force) {
    if (!controlPath || !rulesPath) return
    if (rulesProc.running) rulesProc.running = false
    rulesProc.command = [controlPath, "rules", rulesPath, force ? "true" : "false"]
    rulesProc.running = true
  }

  function handleHyprlandEvent(event) {
    var name = String(event && event.name ? event.name : "")
    if (name === "openlayer") {
      var openedLayer = String(Model.eventParts(event, 1)[0] || "")
      if (openedLayer === "omarchy-image-selector") {
        themePickerOpen = true
        themeFocusLost = opened
        dismissFocusDelay.stop()
        pendingFocusAddress = ""
      }
      return
    }

    if (name === "closelayer") {
      var closedLayer = String(Model.eventParts(event, 1)[0] || "")
      if (closedLayer === "omarchy-image-selector" && themePickerOpen) {
        themePickerOpen = false
        if (opened) themeRefocusDelay.restart()
      }
      return
    }

    if (name === "configreloaded") {
      ruleReload.restart()
      return
    }

    if (name === "activespecial") {
      var specialName = String(Model.eventParts(event, 2)[0] || "")
      if (Model.isParkingSpecial(specialName)) dismissParkingOverlay()
      requestState("sync", null)
      return
    }

    if (name === "openwindow") {
      requestState("sync", null)
      return
    }

    if (name === "closewindow") {
      var closed = Model.normalizeAddress(Model.eventParts(event, 1)[0])
      if (closed && closed === windowAddress) {
        windowAddress = ""
        browserPid = 0
        opened = false
        ownerScreen = ""
        dismissArmed = false
        dismissFocusDelay.stop()
        themeRefocusDelay.stop()
        themeFocusLost = false
        themePickerOpen = false
        pendingFocusAddress = ""
        themeFocusUntil = 0
        actionQueued = ""
        actionQueuedAnchor = null
        setClickaway(false)
      }
      return
    }

    if (name === "activewindowv2" && dismissArmed) {
      var focused = Model.normalizeAddress(Model.eventParts(event, 1)[0])
      var disposition = Model.focusDisposition(
        opened,
        focused,
        windowAddress,
        themeFocusProtected()
      )
      if (disposition === "restore") {
        dismissFocusDelay.stop()
        pendingFocusAddress = ""
        themeFocusLost = true
        protectThemeFocus(12000)
        if (!themePickerOpen) themeRefocusDelay.restart()
      } else if (disposition === "dismiss") {
        pendingFocusAddress = focused
        dismissFocusDelay.restart()
      } else {
        dismissFocusDelay.stop()
        pendingFocusAddress = ""
        themeFocusLost = false
      }
    }
  }

  function initialize() {
    if (!controlPath) return
    var first = initializedFor !== controlPath
    initializedFor = controlPath
    installRules(true)
    setClickaway(false)
    if (!rulesInstalled) rulesRetry.restart()
    if (first) requestState("sync", null)
  }

  onControlPathChanged: initialize()

  Component.onCompleted: Qt.callLater(function() {
    root.initialize()
  })

  Process {
    id: stateProc
    stdout: StdioCollector {
      onStreamFinished: root.stateOutput = text
    }
    onExited: function(code) {
      var intent = root.stateIntent
      var anchor = root.stateAnchor
      root.stateIntent = ""
      root.stateAnchor = null
      if (code === 0) root.handleState(root.stateOutput, intent, anchor)
      else if (intent !== "sync" && intent !== "awaitLaunch")
        root.notifyFailure("Hyprland is not available")
      Qt.callLater(root.drainStateQueue)
    }
  }

  Process {
    id: launchProc
    onExited: function(code) {
      if (code !== 0) {
        root.launching = false
        root.notifyFailure("Could not launch Chromium")
        return
      }
      launchPoll.restart()
    }
  }

  Timer {
    id: launchPoll
    interval: 250
    repeat: true
    onTriggered: {
      if (root.launchAttempts >= 40) {
        launchPoll.stop()
        root.launching = false
        root.notifyFailure("Chromium did not create the YouTube Music window")
        return
      }
      root.launchAttempts++
      root.requestState("awaitLaunch", root.launchAnchor)
    }
  }

  Process {
    id: actionProc
    onExited: function(code) {
      var finishedKind = root.actionKind
      root.actionKind = ""
      if (code !== 0) {
        root.notifyFailure(finishedKind === "hide"
          ? "Could not hide the YouTube Music window"
          : "Could not position the YouTube Music window")
      } else {
        root.lastError = ""
      }
      // Ground truth first: re-read the real window state instead of
      // assuming the action had the intended effect. Queued intents are
      // decided from that fresh state in handleState.
      root.requestState("sync", null)
      if (root.actionQueued !== "") {
        var intent = root.actionQueued
        var anchor = root.actionQueuedAnchor
        root.actionQueued = ""
        root.actionQueuedAnchor = null
        Qt.callLater(function() {
          if (intent === "hide") root.hide()
          else root.requestState(intent, anchor)
        })
      }
    }
  }

  Timer {
    id: dismissDelay
    interval: 350
    onTriggered: root.dismissArmed = root.opened
  }

  Timer {
    id: dismissFocusDelay
    interval: 140
    onTriggered: {
      if (root.themeFocusProtected()) {
        root.themeFocusLost = root.opened
        root.protectThemeFocus(12000)
        if (!root.themePickerOpen) themeRefocusDelay.restart()
      } else if (Model.shouldDismissWindow(
        root.opened,
        root.pendingFocusAddress,
        root.windowAddress
      )) {
        root.hide()
      }
      root.pendingFocusAddress = ""
    }
  }

  Timer {
    id: themeRefocusDelay
    interval: 350
    onTriggered: {
      if (!root.themeFocusLost || !root.opened || !root.windowAddress) {
        root.themeFocusLost = false
        return
      }
      root.themeFocusLost = false
      themeRefocusProc.command = [root.controlPath, "focus", root.windowAddress]
      themeRefocusProc.running = true
    }
  }

  Process {
    id: themeRefocusProc
  }

  Process {
    id: clickawayProc
  }

  Process {
    id: dismissSpecialProc
  }

  Process {
    id: rulesProc
    stdout: StdioCollector {
      onStreamFinished: {
        if (String(text).indexOf("installed") !== -1 || String(text).indexOf("already") !== -1 || String(text).indexOf("ok") !== -1)
          root.rulesInstalled = true
      }
    }
    stderr: StdioCollector {
      onStreamFinished: if (String(text).trim() !== "") console.warn("youtube-music rules:", text)
    }
    onExited: function(code) {
      if (code === 0) root.rulesInstalled = true
      else {
        root.rulesInstalled = false
        console.warn("youtube-music: could not install runtime window rules")
        rulesRetry.restart()
      }
    }
  }

  Timer {
    id: rulesRetry
    interval: 1200
    onTriggered: if (!root.rulesInstalled) root.installRules(true)
  }

  Timer {
    id: ruleReload
    interval: 400
    onTriggered: root.installRules(true)
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  IpcHandler {
    target: "youtube-music"

    function open(): string { root.show(root.lastAnchor); return "ok" }
    function close(): string { root.hide(); return "ok" }
    function show(): string { root.show(root.lastAnchor); return "ok" }
    function hide(): string { root.hide(); return "ok" }
    function toggle(): string { root.toggle(root.lastAnchor); return "ok" }
    function playPause(): string { return root.runAction("playPause") ? "ok" : "unavailable" }
    function next(): string { return root.runAction("next") ? "ok" : "unavailable" }
    function previous(): string { return root.runAction("previous") ? "ok" : "unavailable" }
    function ping(): string {
      if (!root.rulesInstalled) root.installRules(true)
      return "ok"
    }

    function status(): string {
      return JSON.stringify({
        windowAddress: root.windowAddress,
        browserPid: root.browserPid,
        opened: root.opened,
        launching: root.launching,
        ownerScreen: root.ownerScreen,
        rulesInstalled: root.rulesInstalled,
        hasMedia: root.hasMedia,
        playing: root.playing,
        title: root.title,
        artist: root.artist,
        lastError: root.lastError,
        sourceDir: root.sourceDir
      })
    }
  }
}
