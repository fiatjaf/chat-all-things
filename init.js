/* eslint-disable no-unused-vars */
/* globals app, appready, localStorage, haiku,
    location */


// machine id -- should unique and the same forever
var machineId = localStorage.getItem('machineId')
if (!machineId) {
  machineId = haiku()
  localStorage.setItem('machineId', machineId)
}


// channel preferences, just fetch them from localStorage
var channelName = window.location.pathname.split('/').slice(-1)[0]
var channelConfig = JSON.parse(localStorage.getItem('channel-' + channelName))
if (!channelConfig) {
  const defaultWebSocketURL = 'wss://sky-sound.hyperdev.space/subnet/' + channelName

  // maybe this channel was reached through a link with a querystring hint of a websocket url/channel
  var hintWebSocketURL = location.search.slice(1)
    .split('&')
    .find(kv => kv.split('=')[0] === 'ws')

  channelConfig = {
    name: channelName,
    websocket: hintWebSocketURL ? hintWebSocketURL.split('=')[1].trim() : defaultWebSocketURL
  }
}


// a list of active channels that we keep manually (see db.js)
var allChannels = JSON.parse(localStorage.getItem('allChannels') || '{}')


// listen an react to UI actions concerning channels
appready(() => {
  app.ports.setChannel.subscribe(function (channel) {
    localStorage.setItem('channel-' + channelConfig.name, JSON.stringify(channel))
    channelConfig = channel
  })
  app.ports.moveToChannel.subscribe(function (toChannel) {
    window.location.href = '/channel/' + toChannel
  })
})
