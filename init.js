/* eslint-disable no-unused-vars */
/* globals app, appready, localStorage, haiku, location */


// machine id -- should unique and the same forever
var machineId = localStorage.getItem('machineId')
if (!machineId) {
  machineId = haiku()
  localStorage.setItem('machineId', machineId)
}
module.exports.machineId = machineId


// channel preferences, just fetch them from localStorage
var channelName = window.location.pathname.split('/').slice(-1)[0]
window.channelConfig = JSON.parse(localStorage.getItem('channel-' + channelName)) || {}
if (!window.channelConfig.websocket) {
  const defaultWebSocketURL = 'wss://sky-sound.hyperdev.space/subnet/' + channelName

  // maybe this channel was reached through a link with a querystring hint of a websocket url/channel
  var hintWebSocketURL = location.search.slice(1)
    .split('&')
    .find(kv => kv.split('=')[0] === 'ws')

  window.channelConfig.websocket = hintWebSocketURL
    ? hintWebSocketURL.split('=')[1].trim()
    : defaultWebSocketURL
}
window.channelConfig.name = channelName
if (window.channelConfig.couch) {
  appready(() => {
    window.couchdbsync = window.db.sync(window.channelConfig.couch, {
      live: true,
      retry: true
    }).on('error', function (e) { console.log('couch replication error', e) })
  })
} else {
  window.channelConfig.couch = ''
}
module.exports.channelConfig = window.channelConfig


// a list of active channels that we keep manually (see db.js)
var allChannels = JSON.parse(localStorage.getItem('allChannels') || '{}')
module.exports.allChannels = allChannels


// listen an react to UI actions concerning channels
appready(() => {
  app.ports.setChannel.subscribe(function (channel) {
    localStorage.setItem('channel-' + window.channelConfig.name, JSON.stringify(channel))
    window.channelConfig = channel

    if (channel.couch !== window.channelConfig.couch) {
      if (window.couchdbsync) {
        window.couchdbsync.cancel()
      }
      window.couchdbsync = window.db.sync(window.channelConfig.couch, {
        live: true,
        retry: true
      }).on('error', function (e) { console.log('couch replication error', e) })
    }
  })
  app.ports.moveToChannel.subscribe(function (toChannel) {
    window.location.href = '/channel/' + toChannel
  })
})
