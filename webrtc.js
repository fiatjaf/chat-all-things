/* globals app, channelConfig, machineId, cleanupReplicator, setReplicator, replicate
    WebRTC */


// setup webrtc
var webrtc = new WebRTC(channelConfig.websocket, {identifier: machineId})
const CONNECTING = 0
const CONNECTED = 1
const CLOSED = 3
webrtc.onconnecting = function (otherMachineId) {
  app.ports.webrtc.send([otherMachineId, CONNECTING])
}
webrtc.onchannelready = function (datachannel, otherMachineId, connName) {
  datachannel.addEventListener('close', e => {
    app.ports.webrtc.send([otherMachineId, CLOSED])
    cleanupReplicator(otherMachineId, connName)
  })

  datachannel.addEventListener('error', e => {
    app.ports.webrtc.send([otherMachineId, CLOSED])
    cleanupReplicator(otherMachineId, connName)
  })

  app.ports.webrtc.send([otherMachineId, CONNECTED])
  setReplicator(otherMachineId, connName, datachannel)

  replicate()
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
setTimeout(() => {
  app.ports.wsConnect.subscribe(function (addr) {
    webrtc.openWebSocket()
  })
}, 1)
