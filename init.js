/* eslint-disable no-unused-vars */
/* globals app, appready, localStorage, haiku */


// machine id -- should unique and the same forever
var machineId = localStorage.getItem('machineId')
if (!machineId) {
  machineId = haiku()
  localStorage.setItem('machineId', machineId)
}


// channel preferences, just fetch them
var channelName = window.location.pathname.split('/').slice(-1)[0]
var channelConfig = JSON.parse(localStorage.getItem('channel-' + channelName))
if (!channelConfig) {
  channelConfig = {
    name: channelName,
    websocket: 'wss://sky-sound.hyperdev.space/subnet/' + channelName
  }
  localStorage.setItem('channel-' + channelName, JSON.stringify(channelConfig))
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
