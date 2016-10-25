/* eslint-disable no-unused-vars */
/* globals app, appready,
    PouchDB, localStorage, haiku, pouchdbEnsure, PouchReplicator */

const channelConfig = require('./init').channelConfig
const allChannels = require('./init').allChannels


// setup database
PouchDB.plugin(pouchdbEnsure)
var db = new PouchDB('channel-' + channelConfig.name)
setTimeout(() => db.viewCleanup(), 5000)
module.exports.db = db


// setup webrtc channel management and pouchdb channelManager
function ChannelManager () {
  this.connections = {}
  this.replicators = {}

  this.set = function (otherMachineId, connName, datachannel) {
    var replicator = this.replicators[otherMachineId] = this.replicators[otherMachineId] ||
      new PouchReplicator('replicator', PouchDB, db, {batch_size: 50})

    replicator.addPeer(connName, datachannel)

    var connections = this.connections[otherMachineId] = this.connections[otherMachineId] || {}
    connections[connName] = datachannel

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

  this.cleanup = function (otherMachineId, connName) {
    var replicator = this.replicators[otherMachineId]
    if (!replicator) return
    replicator.removePeer(connName)
  }

  this.replicate = function () {
    console.log('replicating pouchdb to', Object.keys(this.replicators))
    for (var otherMachineId in this.replicators) {
      console.log('> replicating pouchdb to', otherMachineId)

      app.ports.replication.send([otherMachineId, '<replicating>'])

      var replicator = this.replicators[otherMachineId]
      replicator.replicate()
    }
  }
}
module.exports.channelManager = new ChannelManager()


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
