/* globals Elm, runElmProgram, PouchDB, cuid, localStorage, pouchdbEnsure, PouchReplicator, WebRTC, haiku */

var machineId = localStorage.getItem('machineId')
if (!machineId) {
  machineId = haiku()
  localStorage.setItem('machineId', machineId)
}

var channelName = window.location.pathname.split('/').slice(-1)[0]
var channelConfig = JSON.parse(localStorage.getItem('channel-' + channelName))
if (!channelConfig) {
  channelConfig = {
    name: channelName,
    lan: false,
    websocket: 'wss://sky-sound.hyperdev.space/subnet'
  }
  localStorage.setItem('channel-' + channelName, JSON.stringify(channelConfig))
}


// setup database
PouchDB.plugin(pouchdbEnsure)
var db = new PouchDB('channel-' + channelName)
setTimeout(() => db.viewCleanup(), 5000)


// setup webrtc and replication
var replicators = {}
function setReplicator (otherMachineId, connName, datachannel) {
  var replicator = replicators[otherMachineId] = replicators[otherMachineId] ||
    new PouchReplicator('replicator', PouchDB, db, {batch_size: 50})

  replicator.addPeer(connName, datachannel)
  replicator.datachannels = replicator.datachannels || {}
  replicator.datachannels[connName] = datachannel

  replicator.on('endpeerreplicate', function () {
    for (var i in replicator.datachannels) {
      var dc = replicator.datachannels[i]
      dc.send('<received>')
    }
    app.ports.replication.send([otherMachineId, '<received>'])
  })

  datachannel.addEventListener('message', e => {
    console.log(connName + ' says: ' + e.data)
    if (e.data === '<received>') {
      app.ports.replication.send([otherMachineId, '<sent>'])
      db.compact()
    }
  })
}

function cleanupReplicator (otherMachineId, connName) {
  var replicator = replicators[otherMachineId]
  if (!replicator) return
  replicator.removePeer(connName)
}

function replicate () {
  console.log('replicating pouchdb to', Object.keys(replicators))
  for (var otherMachineId in replicators) {
    console.log('> replicating pouchdb to', otherMachineId)

    app.ports.replication.send([otherMachineId, '<replicating>'])

    var replicator = replicators[otherMachineId]
    replicator.replicate()
  }
}

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

  // try again in 2 minutes
  setTimeout(function () { webrtc.openWebSocket() }, 120000)
}


// one doc in the database is sufficient to mark this channel as existing
var allChannels = JSON.parse(localStorage.getItem('allChannels') || '{}')
db.allDocs({limit: 1, startkey: 'A'})
.then(res => {
  if (res.rows.length) {
    allChannels[channelName] = true
    localStorage.setItem(
      'allChannels',
      JSON.stringify(allChannels)
    )
  }
})


// run elm app
var app
try {
  app = Elm.App.fullscreen({
    machineId: machineId,
    channel: channelConfig,
    allChannels: Object.keys(allChannels)
  })
} catch (e) {
  var stylesheets = document.querySelectorAll('link')
  for (var i = 0; i < stylesheets.length; i++) {
    stylesheets[i].parentNode.removeChild(stylesheets[i])
  }
  runElmProgram()
}


// elm app ports
app.ports.wsConnect.subscribe(function () {
  webrtc.openWebSocket()
})
app.ports.updateCardContents.subscribe(function (data) {
  var id = data[0]
  var index = data[1]
  var value = data[2]
  db.get(id, function (err, card) {
    if (err) {
      console.log('failed to fetch', id, 'to update', err)
    } else {
      if (index === -1) {
        // special case for updating the card name
        if (card.name !== value) {
          card.name = value
          db.put(card)
            .then(replicate)
        }
      } else if (value === null) {
        // deleting a content
        if (card.contents[index]) {
          card.contents.splice(index, 1)
          db.put(card)
            .then(replicate)
        }
      } else if (typeof card.contents[index] === 'undefined') {
        // adding content (either text or conversation)
        card.contents.push(value)
        db.put(card)
          .then(replicate)
      } else if (card.contents[index] !== value) {
        // updating text content
        card.contents[index] = value
        db.put(card)
          .then(replicate)
      }
    }
  })
})

app.ports.pouchCreate.subscribe(function (doc) {
  if (doc.author && doc.text) {
    doc._id = 'message-' + cuid()
  } else if ('name' in doc && doc.contents) {
    doc._id = 'card-' + cuid()
  } else {
    return
  }

  delete doc.type
  db.put(doc)
    .then(replicate)
  .then(() => {
    if (doc._id.split('-')[0] === 'card') app.ports.cardLoaded.send(doc)
  })
})
app.ports.loadCard.subscribe(function (id) {
  db.get(id, function (err, doc) {
    if (err) {
      console.log('could not get doc', id)
    } else {
      app.ports.cardLoaded.send(doc)
    }
  })
})
app.ports.setUserPicture.subscribe(function (data) {
  var name = data[0]
  var pictureURL = data[1]
  var userId = `user-${machineId}-${name}`

  db.get(userId)
  .catch(() => {
    // if the new user is being created, we should select him
    localStorage.setItem('lastuser-' + channelName, name)

    return {
      _id: userId,
      name: name,
      machineId: machineId
    }
  })
  .then(doc => {
    doc.pictureURL = pictureURL
    return db.put(doc)
             .then(replicate)
  })
  .catch(e => console.log('failed to save user with picture', e))
})
app.ports.setChannel.subscribe(function (channel) {
  localStorage.setItem('channel-' + channelName, JSON.stringify(channel))
  channelConfig = channel
})

app.ports.moveToChannel.subscribe(function (channelName) {
  window.location.href = '/channel/' + channelName
})
app.ports.userSelected.subscribe(function (name) {
  localStorage.setItem('lastuser-' + channelName, name)
})
app.ports.focusField.subscribe(function (selector) {
  setTimeout(function () {
    document.querySelector(selector).focus()
  }, 1)
})
app.ports.scrollChat.subscribe(function (timeout) {
  setTimeout(function () {
    document.getElementById('messages').scrollTop = 99999
  }, timeout)
})
app.ports.deselectText.subscribe(function (timeout) {
  setTimeout(function () {
    if (document.selection) {
      document.selection.empty()
    } else if (window.getSelection) {
      window.getSelection().removeAllRanges()
    }
  }, timeout)
})


// listen for db changes
db.changes({
  live: true,
  include_docs: true,
  return_docs: false
}).on('change', function (change) {
  if (change.doc._deleted) {
    return
  }

  switch (change.doc._id.split('-')[0]) {
    case 'message':
      app.ports.pouchMessages.send(change.doc)
      break
    case 'card':
      app.ports.pouchCards.send(change.doc)
      break
    case 'user':
      app.ports.pouchUsers.send(change.doc)
      break
  }
}).on('error', function (err) {
  console.log('pouchdb changes error:', err)
})


// get information about the current user
db.allDocs({startkey: 'user-', endkey: 'user-{', include_docs: true})
.then(res => {
  if (res.rows.length === 0) {
    // do nothing.
  } else if (res.rows.length === 1) {
    app.ports.currentUser.send(res.rows[0].doc)
  } else {
    var lastUserName = localStorage.getItem('lastuser-' + channelName)
    if (lastUserName) {
      var found = res.rows.find(row => row.doc.name === lastUserName)
      if (found) {
        app.ports.currentUser.send(found.doc)
      }
    }
  }
})


// register service worker
if (navigator.serviceWorker) {
  navigator.serviceWorker.register('/serviceworker.js')
}
