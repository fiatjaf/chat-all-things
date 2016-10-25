/* globals app, appready
    WebRTC */

const machineId = require('./init').machineId
const channelConfig = require('./init').channelConfig
const channelManager = require('./db').channelManager


// setup webrtc
var webrtc = new WebRTC(channelConfig.websocket, {identifier: machineId})
module.exports.webrtc = webrtc
const CONNECTING = 0
const CONNECTED = 1
const CLOSED = 3
webrtc.onconnecting = function (otherMachineId) {
  app.ports.webrtc.send([otherMachineId, CONNECTING])
}
webrtc.onchannelready = function (datachannel, otherMachineId, connName) {
  datachannel.addEventListener('close', e => {
    app.ports.webrtc.send([otherMachineId, CLOSED])
    channelManager.cleanup(otherMachineId, connName)
  })

  datachannel.addEventListener('error', e => {
    app.ports.webrtc.send([otherMachineId, CLOSED])
    channelManager.cleanup(otherMachineId, connName)
  })

  app.ports.webrtc.send([otherMachineId, CONNECTED])
  channelManager.set(otherMachineId, connName, datachannel)

  channelManager.replicate()
}
webrtc.onwsconnected = function () {
  app.ports.websocket.send(true)
}
webrtc.onwsdisconnected = function () {
  app.ports.websocket.send(false)

  // start connecting again in 2 minutes
  setTimeout(function () { webrtc.openWebSocket() }, 120000)
}


// start connecting when requested from UI
appready(() => {
  app.ports.wsConnect.subscribe(function (addr) {
    webrtc.openWebSocket()
  })
})
