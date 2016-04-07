_          = require 'lodash'
redis      = require 'fakeredis'
RedisNS    = require '@octoblu/redis-ns'
mongojs    = require 'mongojs'
uuid       = require 'uuid'
Datastore  = require 'meshblu-core-datastore'
JobManager = require 'meshblu-core-job-manager'
EnqueueJobsForSubscriptionsMessageReceived = require '../'

describe 'EnqueueJobsForSubscriptionsMessageReceived', ->
  beforeEach (done) ->
    @datastore = new Datastore
      database: mongojs 'subscription-test'
      collection: 'subscriptions'
    @datastore.remove done

  beforeEach ->
    @redisKey = uuid.v1()
    @jobManager = new JobManager
      client: new RedisNS 'ns', redis.createClient(@redisKey)
      timeoutSeconds: 1

  beforeEach ->
    client = new RedisNS 'ns', redis.createClient(@redisKey)

    @sut = new EnqueueJobsForSubscriptionsMessageReceived {
      datastore: @datastore
      jobManager: new JobManager {client: client, timeoutSeconds: 1}
      uuidAliasResolver: {resolve: (uuid, callback) -> callback(null, uuid)}
    }

  describe '->do', ->
    context 'when there are no subscriptions', ->
      context 'when given a request', ->
        beforeEach (done) ->
          request =
            metadata:
              responseId: 'its-electric'
              fromUuid: 'emitter-uuid'
              toUuid: 'subscriber-uuid'
              options: {}
            rawData: '{}'

          @sut.do request, (error, @response) => done error

        it 'should return a 204', ->
          expectedResponse =
            metadata:
              responseId: 'its-electric'
              code: 204
              status: 'No Content'

          expect(@response).to.deep.equal expectedResponse

    context 'when there is one subscription', ->
      beforeEach (done) ->
        record =
          type: 'message.received'
          emitterUuid: 'subscriber-uuid'
          subscriberUuid: 'some-other-uuid'

        @datastore.insert record, done

      context 'when given a message', ->
        beforeEach (done) ->
          request =
            metadata:
              responseId: 'its-electric'
              fromUuid: 'emitter-uuid'
              toUuid: 'subscriber-uuid'
              options: {}
            rawData: '{"original":"message"}'

          @sut.do request, (error, @response) => done error

        it 'should return a 204', ->
          expectedResponse =
            metadata:
              responseId: 'its-electric'
              code: 204
              status: 'No Content'

          expect(@response).to.deep.equal expectedResponse

        it 'should enqueue a job to deliver the message', (done) ->
          @jobManager.getRequest ['request'], (error, request) =>
            return done error if error?
            delete request?.metadata?.responseId
            expect(request).to.deep.equal {
              metadata:
                jobType: 'DeliverSubscriptionMessageReceived'
                auth:
                  uuid: 'some-other-uuid'
                fromUuid: 'subscriber-uuid'
                toUuid: 'some-other-uuid'
                route: [
                 {
                   from: "emitter-uuid"
                   to: "subscriber-uuid"
                   type: "message.received"
                 }
               ]
              rawData: '{"original":"message"}'
            }
            done()

      context 'when given a message with a previous hop in the route', ->
        beforeEach (done) ->
          request =
            metadata:
              responseId: 'its-electric'
              fromUuid: 'emitter-uuid'
              toUuid: 'subscriber-uuid'
              options: {}
              route: [{
                from: 'original-uuid'
                to: 'emitter-uuid'
                type: 'message.sent'
              }]
            rawData: '{"original":"message"}'

          @sut.do request, (error, @response) => done error

        it 'should return a 204', ->
          expectedResponse =
            metadata:
              responseId: 'its-electric'
              code: 204
              status: 'No Content'

          expect(@response).to.deep.equal expectedResponse

        it 'should enqueue a job to deliver the message with the hop prepended', (done) ->
          @jobManager.getRequest ['request'], (error, request) =>
            return done error if error?
            delete request?.metadata?.responseId
            expect(request).to.deep.equal {
              metadata:
                jobType: 'DeliverSubscriptionMessageReceived'
                auth:
                  uuid: 'some-other-uuid'
                fromUuid: 'subscriber-uuid'
                toUuid: 'some-other-uuid'
                route: [
                  {
                    from: "emitter-uuid"
                    to: "subscriber-uuid"
                    type: "message.received"
                  },
                  {
                    from: 'original-uuid'
                    to: 'emitter-uuid'
                    type: 'message.sent'
                  }
                ]
              rawData: '{"original":"message"}'
            }
            done()

      context 'when given a message with a hop in the route equal to this one', ->
        beforeEach (done) ->
          request =
            metadata:
              responseId: 'its-electric'
              fromUuid: 'emitter-uuid'
              toUuid: 'original-uuid'
              options: {}
              route: [{
                from: 'emitter-uuid'
                to: 'original-uuid'
                type: 'message.received'
              }]
            rawData: '{"original":"message"}'

          @sut.do request, (error, @response) => done error

        it 'should return a 204', ->
          expectedResponse =
            metadata:
              responseId: 'its-electric'
              code: 204
              status: 'No Content'

          expect(@response).to.deep.equal expectedResponse

        it 'should not enqueue a job', (done) ->
          @jobManager.getRequest ['request'], (error, request) =>
            return done error if error?
            expect(request).not.to.exist
            done()
