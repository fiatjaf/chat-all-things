/* eslint-disable no-undef, no-unused-vars */

function WebRTC (wsAddress, params) {
  var self = this

  this.address = wsAddress
  this._ws = params.wsClient
  this.identifier = params.identifier || 'id-' + parseInt(Math.random() * 100000000)

  this.onchannelready = function () {}

  this.ws = function ws () {
    if (self._ws && self._ws.readyState <= WebSocket.OPEN) {
      return self._ws
    }
    self._ws = new WebSocket(self.address)
    return self._ws
  }

  this._connections = {}
  this.connection = function (name) {
    var newname = 'conn-' + parseInt(Math.random() * 100000000)
    name = name || newname

    var connection = self._connections[name] = self._connections[name] ||
    new RTCPeerConnection({iceServers: [
      {urls: ['stun:stun.l.google.com:19305']},
      {urls: ['stun:stun1.l.google.com:19305']},
      {urls: ['stun:stun2.l.google.com:19305']},
      {urls: ['stun:stun3.l.google.com:19305']},
      {urls: ['stun:stun.jappix.com:3478']}
    ]})

    connection.name = name

    connection.ondatachannel = function (e) {
      var channel = e.channel
      channel.onopen = e => {
        self.onchannelready(channel, connection.name)
      }
      channel.onclose = e => console.log('channel closed', e)
      channel.onerror = e => console.log('channel error', e)
    }

    connection.onicecandidate = function (e) {
      if (!e.candidate) return
      console.log('got ice candidate for ', connection.name)
      send({
        action: 'candidate',
        data: e.candidate,
        conn: connection.name
      })
    }

    connection.pendingCandidates = []
    connection.hasDescription = false

    return connection
  }

  this.connect = function connect () {
    var ws = self.ws()

    // accepting offers from anywhere
    ws.onclose = e => console.log('websocket closed', e)
    ws.onerror = e => console.log('websocket error', e)
    ws.onmessage = e => {
      var connection
      var data
      try {
        data = JSON.parse(e.data)
      } catch (e) {}
      if (data && data.from !== self.identifier) {
        console.log('got ' + data.action.toUpperCase() + ' on ' + data.conn)
        switch (data.action) {
          case 'candidate':
            connection = self.connection(data.conn)
            var c = new RTCIceCandidate(data.data)
            if (connection.hasDescription) {
              connection.addIceCandidate(c)
                .then(() => console.log('added ice candidate'))
                .catch(e => console.log('add ice error', e))
            } else {
              connection.pendingCandidates.push(c)
            }
            break
          case 'offer':
            connection = self.connection(data.conn)
            connection.setRemoteDescription(new RTCSessionDescription(data.data))
              .then(() => connection.hasDescription = true)
              .then(() => connection.pendingCandidates.forEach(c => connection.addIceCandidate(c)))
              .then(() => connection.createAnswer())
              .then(sdp => {
                send({
                  action: 'answer',
                  data: sdp,
                  conn: data.conn
                })
                connection.setLocalDescription(sdp)
              })
              .then(() => console.log('offer handled'))
              .catch(e => console.log('error handling offer', e))
            break
          case 'answer':
            connection = self.connection(data.conn)
            connection.setRemoteDescription(new RTCSessionDescription(data.data))
              .then(() => connection.hasDescription = true)
              .then(() => connection.pendingCandidates.forEach(c => connection.addIceCandidate(c)))
              .then(() => console.log('answer handled'))
              .catch(e => console.log('error handling answer', e))
            break
        }
      }
    }

    // send an offer to nowhere
    var connection = self.connection()
    var channel = connection.createDataChannel('main-channel')
    channel.onopen = e => {
      self.onchannelready(channel, connection.name)
    }
    channel.onclose = e => console.log('channel closed', e)
    channel.onerror = e => console.log('channel error', e)

    connection.createOffer()
      .then(sdp => {
        connection.setLocalDescription(sdp)
        send({
          action: 'offer',
          data: sdp,
          conn: connection.name
        })
        console.log('sent OFFER on ' + connection.name)
      })
      .catch(e => {
        console.log('error creating and sending offer', e)
        reject(e)
      })
  }

  function send (message) {
    var ws = self.ws()
    switch (ws.readyState) {
      case WebSocket.OPEN:
        message.from = this.identifier
        ws.send(JSON.stringify(message))
        break
      case WebSocket.CONNECTING:
        setTimeout(function () {
          send(message)
        }, 200)
        break
      default:
        reload()
    }
  }
}
