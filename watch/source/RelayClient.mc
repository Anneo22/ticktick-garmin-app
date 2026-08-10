using Toybox.Communications as Comm;
using Toybox.Timer as Timer;
import Toybox.Lang;

class RelayRequest {
    var callback;
    var requestTimer;
    var finished;
    var timeoutMs;

    function initialize(done, timeout) {
        callback = done;
        requestTimer = null;
        finished = false;
        timeoutMs = timeout;
    }

    function start(url, payload, options) {
        try {
            requestTimer = new Timer.Timer();
            requestTimer.start(method(:onTimeout), timeoutMs, false);
            Comm.makeWebRequest(url, payload, options, method(:onResponse));
        } catch (error) {
            cancel();
            return false;
        }
        return true;
    }

    function cancel() as Void {
        finished = true;
        callback = null;
        if (requestTimer != null) {
            try {
                requestTimer.stop();
            } catch (error) {
            }
            requestTimer = null;
        }
    }

    function onTimeout() as Void {
        finish(-1001, null, false);
    }

    function onResponse(responseCode as Number, data as Dictionary or String or Null) as Void {
        finish(responseCode, data, true);
    }

    function finish(responseCode, data, stopTimer) as Void {
        if (finished) {
            return;
        }
        finished = true;
        if (stopTimer && requestTimer != null) {
            try {
                requestTimer.stop();
            } catch (error) {
            }
        }
        requestTimer = null;
        var done = callback;
        callback = null;
        if (done != null) {
            done.invoke(responseCode, data);
        }
    }
}

class RelayClient {
    const RELAY_URL = "https://ticktick-garmin-relay.garmin-bridge.workers.dev";
    const REQUEST_TIMEOUT_MS = 20000;

    var store;
    var activeRequest;
    var activeCallback;

    function initialize(localStore) {
        store = localStore;
        activeRequest = null;
        activeCallback = null;
    }

    function jsonOptions(method, authenticated) {
        var headers = {
            "Content-Type" => Comm.REQUEST_CONTENT_TYPE_JSON
        };
        if (authenticated) {
            headers["Authorization"] = "Bearer " + store.getRelayToken();
        }
        return {
            :method => method,
            :headers => headers,
            :responseType => Comm.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
    }

    function request(path, payload, method, authenticated, done) {
        if (activeRequest != null) {
            return false;
        }
        activeCallback = done;
        activeRequest = new RelayRequest(method(:finishRequest), REQUEST_TIMEOUT_MS);
        var options;
        try {
            options = jsonOptions(method, authenticated);
        } catch (error) {
            activeRequest.cancel();
            activeRequest = null;
            activeCallback = null;
            return false;
        }
        if (!activeRequest.start(RELAY_URL + path, payload, options)) {
            activeRequest = null;
            activeCallback = null;
            return false;
        }
        return true;
    }

    function finishRequest(responseCode, data) as Void {
        activeRequest = null;
        var done = activeCallback;
        activeCallback = null;
        if (done != null) {
            done.invoke(responseCode, data);
        }
    }

    function startPair(done) {
        return request("/v1/pair/start", {}, Comm.HTTP_REQUEST_METHOD_POST, false, done);
    }

    function pollPair(deviceSecret, done) {
        return request("/v1/pair/status", {"deviceSecret" => deviceSecret}, Comm.HTTP_REQUEST_METHOD_POST, false, done);
    }

    function taskPath(view, projectId, utcOffsetMinutes, cursor) {
        var path = "/v1/tasks?view=" + view;
        if (view.equals("project")) {
            path += "&projectId=" + projectId;
        } else {
            path += "&utcOffsetMinutes=" + utcOffsetMinutes.format("%d");
        }
        if (cursor != null) {
            path += "&cursor=" + cursor;
        }
        return path;
    }

    function fetchTasks(view, projectId, utcOffsetMinutes, cursor, done) {
        var path = taskPath(view, projectId, utcOffsetMinutes, cursor);
        return request(path, null, Comm.HTTP_REQUEST_METHOD_GET, true, done);
    }

    function fetchProjects(cursor, done) {
        var path = "/v1/projects";
        if (cursor != null) {
            path += "?cursor=" + cursor;
        }
        return request(path, null, Comm.HTTP_REQUEST_METHOD_GET, true, done);
    }

    function unpair(done) {
        return request("/v1/unpair", {}, Comm.HTTP_REQUEST_METHOD_POST, true, done);
    }

    function completeTask(task, mutationId, done) {
        return request(
            "/v1/tasks/" + task["id"] + "/complete",
            {"projectId" => task["projectId"], "mutationId" => mutationId},
            Comm.HTTP_REQUEST_METHOD_POST,
            true,
            done
        );
    }

    function replayComplete(mutation, done) {
        return request(
            "/v1/tasks/" + mutation["taskId"] + "/complete",
            {"projectId" => mutation["projectId"], "mutationId" => mutation["mutationId"]},
            Comm.HTTP_REQUEST_METHOD_POST,
            true,
            done
        );
    }

}
