/* eslint-disable no-unused-vars */
/* globals app, appready, channelConfig, allChannels
    PouchDB, localStorage, haiku, pouchdbEnsure, PouchReplicator */


// setup database
PouchDB.plugin(pouchdbEnsure)
var db = new PouchDB('channel-' + channelConfig.name)
setTimeout(() => db.viewCleanup(), 5000)


// setup webrtc replicators
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


// mark this channel as existing.
// one doc in the database is sufficient to consider it existent.
db.allDocs({limit: 1, startkey: 'A'})
.then(res => {
  if (res.rows.length) {
    allChannels[channelConfig.name] = true
    localStorage.setItem(
      'allChannels',
      JSON.stringify(allChannels)
    )
  }
})


// get information about the current user and pass it to the app
db.allDocs({startkey: 'user-', endkey: 'user-{', include_docs: true})
.then(res => {
  if (res.rows.length === 0) {
    // do nothing.
  } else if (res.rows.length === 1) {
    app.ports.currentUser.send(res.rows[0].doc)
  } else {
    var lastUserName = localStorage.getItem('lastuser-' + channelConfig.name)
    if (lastUserName) {
      var found = res.rows.find(row => row.doc.name === lastUserName)
      if (found) {
        app.ports.currentUser.send(found.doc)
      }
    }
  }
})


// listen for db changes and react accordingly
appready(() => {
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
})
