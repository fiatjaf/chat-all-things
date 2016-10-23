/* globals Elm, runElmProgram, PouchDB, cuid, localStorage, pouchdbEnsure, PouchReplicator, WebRTC */

var machineId = localStorage.getItem('machineId')
if (!machineId) {
  machineId = cuid.slug()
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
var replicator = new PouchReplicator('replicator', PouchDB, db, {batch_size: 50})
replicator.on('endpeerreplicate', function () {
  console.log('received data from replication')
  datachannels.forEach(dc => dc.send('received replicated data'))
})
setTimeout(() => db.viewCleanup(), 5000)

function replicate () {
  console.log('replicating pouchdb')
  replicator.replicate()
}


// setup webrtc
var webrtc = new WebRTC(channelConfig.websocket, {identifier: machineId})
var datachannels = []
webrtc.onchannelready = function (datachannel, connName) {
  console.log('datachannel ready')
  replicator.addPeer(connName, datachannel)
  datachannels.push(datachannel)

  datachannel.addEventListener('message', e => {
    console.log(connName + ' says: ' + e.data)
    if (e.data === 'received replicated data') {
      db.compact()
    }
  })

  datachannel.addEventListener('closed', e => {
    app.ports.webrtc.send('CLOSED')
  })

  datachannel.addEventListener('error', e => {
    app.ports.webrtc.send('CLOSED')
  })

  app.ports.webrtc.send('CONNECTED')

  replicate()
}
webrtc.onwsdisconnected = function () {
  app.ports.webrtc.send('CLOSED')
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
app.ports.connect.subscribe(function () {
  webrtc.connect()
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
