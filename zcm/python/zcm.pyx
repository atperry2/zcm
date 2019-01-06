from libc.stdint cimport uint64_t, int64_t, int32_t, uint32_t, uint8_t
from posix.unistd cimport off_t
import time

cdef extern from "Python.h":
    void PyEval_InitThreads()

cdef extern from "zcm/zcm_base_types.h":
    ctypedef  uint8_t    zbool_t
    ctypedef     char    zchar_t
    ctypedef  uint8_t   zuint8_t
    ctypedef uint32_t  zuint32_t
    ctypedef uint64_t  zuint64_t
    ctypedef    off_t     zoff_t

cdef extern from "zcm/zcm.h":
    cdef enum zcm_return_codes:
        ZCM_EOK
        pass
    ctypedef zcm_return_codes zcm_retcode_t

    ctypedef struct zcm_t:
        pass

    ctypedef struct zcm_sub_t:
        pass

    ctypedef struct zcm_recv_buf_t:
        zuint8_t* data
        zuint32_t data_size
        pass

    ctypedef void (*zcm_msg_handler_t)(const zcm_recv_buf_t* rbuf, const zchar_t* channel, void* usr)

    zcm_t* zcm_create (const zchar_t* url)
    void   zcm_destroy(zcm_t* zcm)

    zcm_retcode_t  zcm_errno   (zcm_t* zcm)
    const zchar_t* zcm_strerror(zcm_t* zcm)
    const zchar_t* zcm_strerrno(zcm_retcode_t err)

    zcm_sub_t*     zcm_try_subscribe  (zcm_t* zcm, const zchar_t* channel,
                                       zcm_msg_handler_t cb, void* usr)
    zcm_retcode_t  zcm_try_unsubscribe(zcm_t* zcm, zcm_sub_t* sub)

    zcm_retcode_t  zcm_publish(zcm_t* zcm, const zchar_t* channel,
                               const zuint8_t* data, zuint32_t dlen)

    zcm_retcode_t  zcm_try_flush         (zcm_t* zcm)

    void          zcm_run               (zcm_t* zcm)
    void          zcm_start             (zcm_t* zcm)
    zcm_retcode_t zcm_try_stop          (zcm_t* zcm)
    void          zcm_pause             (zcm_t* zcm)
    void          zcm_resume            (zcm_t* zcm)
    zcm_retcode_t zcm_handle            (zcm_t* zcm)
    zcm_retcode_t zcm_try_set_queue_size(zcm_t* zcm, zuint32_t numMsgs)

    zcm_retcode_t  zcm_handle_nonblock(zcm_t* zcm)

    ctypedef struct zcm_eventlog_t:
        pass

    ctypedef struct zcm_eventlog_event_t:
        zuint64_t  eventnum
        zuint64_t  timestamp
        zuint32_t  channellen
        zuint32_t  datalen
        zchar_t*  channel
        zuint8_t*  data

    zcm_eventlog_t* zcm_eventlog_create(const zchar_t* path, const zchar_t* mode)
    void            zcm_eventlog_destroy(zcm_eventlog_t* eventlog)

    zcm_retcode_t zcm_eventlog_seek_to_timestamp(zcm_eventlog_t* eventlog, zuint64_t ts)

    zcm_eventlog_event_t* zcm_eventlog_read_next_event(zcm_eventlog_t* eventlog)
    zcm_eventlog_event_t* zcm_eventlog_read_prev_event(zcm_eventlog_t* eventlog)
    zcm_eventlog_event_t* zcm_eventlog_read_event_at_offset(zcm_eventlog_t* eventlog,
                                                            zoff_t offset)
    void                  zcm_eventlog_free_event(zcm_eventlog_event_t* event)
    zbool_t               zcm_eventlog_write_event(zcm_eventlog_t* eventlog, \
                                                   const zcm_eventlog_event_t* event)

cdef class ZCMSubscription:
    cdef zcm_sub_t* sub
    cdef object handler
    cdef object msgtype

cdef void handler_cb(const zcm_recv_buf_t* rbuf, const zchar_t* channel, void* usr) with gil:
    subs = (<ZCMSubscription>usr)
    msg = subs.msgtype.decode(rbuf.data[:rbuf.data_size])
    subs.handler(channel.decode('utf-8'), msg)

cdef void handler_cb_raw(const zcm_recv_buf_t* rbuf, const zchar_t* channel, void* usr) with gil:
    subs = (<ZCMSubscription>usr)
    subs.handler(channel.decode('utf-8'), rbuf.data[:rbuf.data_size])

cdef class ZCM:
    cdef zcm_t* zcm
    cdef object subscriptions
    def __cinit__(self, str url=""):
        PyEval_InitThreads()
        self.subscriptions = []
        self.zcm = zcm_create(url.encode('utf-8'))
    def __dealloc__(self):
        if self.zcm == NULL:
            return
        self.stop()
        while len(self.subscriptions) > 0:
            self.unsubscribe(self.subscriptions[0]);
        zcm_destroy(self.zcm)
    def good(self):
        return self.zcm != NULL
    def err(self):
        return zcm_errno(self.zcm)
    def strerror(self):
        return zcm_strerror(self.zcm).decode('utf-8')
    def strerrno(self, err):
        return zcm_strerrno(err).decode('utf-8')
    def subscribe_raw(self, str channel, handler):
        cdef ZCMSubscription subs = ZCMSubscription()
        subs.handler = handler
        subs.msgtype = None
        while True:
            subs.sub = zcm_try_subscribe(self.zcm, channel.encode('utf-8'), handler_cb_raw, <void*> subs)
            if subs.sub != NULL:
                self.subscriptions.append(subs)
                return subs
            time.sleep(0) # yield the gil
    def subscribe(self, str channel, msgtype, handler):
        cdef ZCMSubscription subs = ZCMSubscription()
        subs.handler = handler
        subs.msgtype = msgtype
        while True:
            subs.sub = zcm_try_subscribe(self.zcm, channel.encode('utf-8'), handler_cb, <void*> subs)
            if subs.sub != NULL:
                self.subscriptions.append(subs)
                return subs
            time.sleep(0) # yield the gil
    def unsubscribe(self, ZCMSubscription subs):
        while zcm_try_unsubscribe(self.zcm, subs.sub) != ZCM_EOK:
            time.sleep(0) # yield the gil
        self.subscriptions.remove(subs)
    def publish(self, str channel, object msg):
        _data = msg.encode()
        cdef const zuint8_t* data = _data
        return zcm_publish(self.zcm, channel.encode('utf-8'), data, len(_data) * sizeof(zuint8_t))
    def flush(self):
        while zcm_try_flush(self.zcm) != ZCM_EOK:
            time.sleep(0) # yield the gil
    def run(self):
        zcm_run(self.zcm)
    def start(self):
        zcm_start(self.zcm)
    def stop(self):
        while zcm_try_stop(self.zcm) != ZCM_EOK:
            time.sleep(0) # yield the gil
    def pause(self):
        zcm_pause(self.zcm)
    def resume(self):
        zcm_resume(self.zcm)
    def handle(self):
        return zcm_handle(self.zcm)
    def setQueueSize(self, numMsgs):
        while zcm_try_set_queue_size(self.zcm, numMsgs) != ZCM_EOK:
            time.sleep(0) # yield the gil
    def handleNonblock(self):
        return zcm_handle_nonblock(self.zcm)

cdef class LogEvent:
    cdef zuint64_t eventnum
    cdef zuint64_t timestamp
    cdef object  channel
    cdef object  data
    def __cinit__(self):
        pass
    def setEventnum(self, zuint64_t eventnum):
        self.eventnum = eventnum
    def getEventnum(self):
        return self.eventnum
    def setTimestamp(self, zuint64_t time):
        self.timestamp = time
    def getTimestamp(self):
        return self.timestamp
    def setChannel(self, basestring chan):
        self.channel = chan.encode('utf-8')
    def getChannel(self):
        return self.channel.decode('utf-8')
    def setData(self, bytes data):
        self.data = data
    def getData(self):
        return self.data

cdef class LogFile:
    cdef zcm_eventlog_t* eventlog
    cdef zcm_eventlog_event_t* lastevent
    def __cinit__(self, str path, str mode):
        self.eventlog = zcm_eventlog_create(path.encode('utf-8'), mode.encode('utf-8'))
        self.lastevent = NULL
    def __dealloc__(self):
        self.close()
    def close(self):
        if self.eventlog != NULL:
            zcm_eventlog_destroy(self.eventlog)
            self.eventlog = NULL
        if self.lastevent != NULL:
            zcm_eventlog_free_event(self.lastevent)
            self.lastevent = NULL
    def good(self):
        return self.eventlog != NULL
    def seekToTimestamp(self, zuint64_t timestamp):
        return zcm_eventlog_seek_to_timestamp(self.eventlog, timestamp)
    cdef __setCurrentEvent(self, zcm_eventlog_event_t* evt):
        if self.lastevent != NULL:
            zcm_eventlog_free_event(self.lastevent)
        self.lastevent = evt
        if evt == NULL:
            return None
        cdef LogEvent curEvent = LogEvent()
        curEvent.eventnum = evt.eventnum
        curEvent.setChannel   (evt.channel[:evt.channellen].decode('utf-8'))
        curEvent.setTimestamp (evt.timestamp)
        curEvent.setData      ((<zuint8_t*>evt.data)[:evt.datalen])
        return curEvent
    def readNextEvent(self):
        cdef zcm_eventlog_event_t* evt = zcm_eventlog_read_next_event(self.eventlog)
        return self.__setCurrentEvent(evt)
    def readPrevEvent(self):
        cdef zcm_eventlog_event_t* evt = zcm_eventlog_read_prev_event(self.eventlog)
        return self.__setCurrentEvent(evt)
    def readEventOffset(self, off_t offset):
        cdef zcm_eventlog_event_t* evt = zcm_eventlog_read_event_at_offset(self.eventlog, offset)
        return self.__setCurrentEvent(evt)
    def writeEvent(self, LogEvent event):
        cdef zcm_eventlog_event_t evt
        evt.eventnum   = event.eventnum
        evt.timestamp  = event.timestamp
        evt.channellen = len(event.channel)
        evt.datalen    = len(event.data)
        evt.channel    = <zchar_t*> event.channel
        evt.data       = <zuint8_t*> event.data
        return zcm_eventlog_write_event(self.eventlog, &evt);
