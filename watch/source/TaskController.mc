using Toybox.System as Sys;
using Toybox.Time as Time;
using Toybox.WatchUi as Ui;
using Toybox.Communications as Comm;
using Toybox.Math as Math;

class TaskController {
    var store;
    var relay;
    var queue;
    var view;
    var tasks;
    var projects;
    var selected;
    var mode;
    var projectId;
    var projectName;
    var status;
    var verificationUrl;
    var pendingTask;
    var pendingMutationId;
    var armedCompletionId;
    var confirmingCompletion;
    var confirmingUnpair;
    var statusBeforeConfirm;
    var reconciliationRequired;
    var busy;
    var nextCursor;
    var pendingViewMode;
    var pendingProjectId;
    var pendingAppend;

    function initialize() {
        store = new LocalStore();
        relay = new RelayClient(store);
        queue = new OfflineQueue(store);
        tasks = store.getTasks();
        projects = [];
        selected = 0;
        mode = "today";
        projectId = null;
        projectName = null;
        status = store.getRelayToken() == null ? (store.getDeviceSecret() == null ? "unpaired" : "pair_pending") : "cached";
        verificationUrl = store.getVerificationUrl();
        pendingTask = null;
        pendingMutationId = null;
        armedCompletionId = null;
        confirmingCompletion = false;
        confirmingUnpair = false;
        statusBeforeConfirm = null;
        reconciliationRequired = false;
        busy = false;
        nextCursor = null;
        pendingViewMode = null;
        pendingProjectId = null;
        pendingAppend = false;
    }

    function attach(taskView) {
        view = taskView;
    }

    function isPaired() {
        return store.getRelayToken() != null;
    }

    function requestUpdate() {
        if (view != null) {
            Ui.requestUpdate();
        }
    }

    function activeItems() {
        if (mode.equals("lists")) {
            return projects;
        }
        return mode.equals("account") ? [] : tasks;
    }

    function completionTask() {
        if (!(armedCompletionId instanceof String)) {
            return null;
        }
        for (var index = 0; index < tasks.size(); index += 1) {
            var taskId = tasks[index]["id"];
            if (taskId instanceof String && taskId.equals(armedCompletionId)) {
                return tasks[index];
            }
        }
        return null;
    }

    // Any navigation or cancellation clears a pending confirmation, even while a request is in flight.
    function disarm() {
        if (!confirmingCompletion && !confirmingUnpair) {
            return false;
        }
        confirmingCompletion = false;
        confirmingUnpair = false;
        armedCompletionId = null;
        if (statusBeforeConfirm != null) {
            status = statusBeforeConfirm;
            statusBeforeConfirm = null;
        }
        requestUpdate();
        return true;
    }

    function arm(confirmStatus) {
        statusBeforeConfirm = status;
        status = confirmStatus;
        requestUpdate();
    }

    // The only way to arm a completion. Never confirms, so repeating it cannot complete a task.
    function armCompletion() {
        if (busy || !isPaired() || reconciliationRequired || confirmingCompletion) {
            return;
        }
        if (mode.equals("account") || mode.equals("lists")) {
            return;
        }
        if (selected < 0 || selected >= tasks.size()) {
            return;
        }
        var taskId = tasks[selected]["id"];
        if (!(taskId instanceof String)) {
            return;
        }
        armedCompletionId = taskId;
        confirmingCompletion = true;
        arm("confirm_complete");
    }

    function activate() {
        // List drilldown is safe navigation. Let it supersede an in-flight list refresh; that
        // stale response will be discarded and resume the selected project's refresh.
        if (mode.equals("lists") && isPaired() && !reconciliationRequired) {
            openSelectedProject();
            return;
        }
        if (busy) {
            return;
        }
        if (!isPaired()) {
            beginOrPollPair();
            return;
        }
        if (reconciliationRequired) {
            refresh();
            return;
        }
        if (mode.equals("account")) {
            if (confirmingUnpair) {
                confirmUnpair();
            } else {
                confirmingUnpair = true;
                arm("confirm_unpair");
            }
            return;
        }
        if (confirmingCompletion) {
            confirmSelectedCompletion();
            return;
        }
        if (tasks.size() == 0) {
            refresh();
            return;
        }
        armCompletion();
    }

    function beginOrPollPair() {
        if (!phoneReady()) {
            recoverRejectedRequest("phone_unavailable");
            return;
        }
        var secret = store.getDeviceSecret();
        busy = true;
        status = "pairing";
        requestUpdate();
        if (secret == null) {
            if (!relay.startPair(method(:onPairStarted))) {
                recoverRejectedRequest("network_error");
            }
        } else {
            if (verificationUrl != null) {
                openVerificationPage();
            }
            if (!relay.pollPair(secret, method(:onPairPolled))) {
                recoverRejectedRequest("network_error");
            }
        }
    }

    function phoneReady() {
        return Sys.getDeviceSettings().phoneConnected;
    }

    function openVerificationPage() {
        if (verificationUrl == null) {
            return false;
        }
        try {
            Comm.openWebPage(verificationUrl, {"code" => store.getUserCode()}, null);
        } catch (error) {
            return false;
        }
        return true;
    }

    function recoverRejectedRequest(failureStatus) {
        busy = false;
        status = failureStatus;
        requestUpdate();
    }

    function onPairStarted(code, response) {
        busy = false;
        if (successfulResponse(code, response) && response["data"] instanceof Dictionary) {
            var data = response["data"];
            store.setPendingPair(data["deviceSecret"], data["userCode"], data["verificationUrl"]);
            verificationUrl = data["verificationUrl"];
            status = "pair_pending";
            if (!openVerificationPage()) {
                status = "phone_unavailable";
            }
        } else {
            status = pairingFailureStatus(code);
        }
        requestUpdate();
    }

    function onPairPolled(code, response) {
        busy = false;
        if (successfulResponse(code, response) && response["data"] instanceof Dictionary) {
            var data = response["data"];
            if (data["status"] instanceof String && data["status"].equals("paired")) {
                store.setRelayToken(data["relayToken"]);
                store.clearPendingPair();
                status = "paired";
                refresh();
                return;
            }
            status = "pair_pending";
        } else if (invalidPairing(response)) {
            store.clearPendingPair();
            verificationUrl = null;
            status = "pair_expired";
        } else {
            status = pairingFailureStatus(code);
        }
        requestUpdate();
    }

    function pairingFailureStatus(code) {
        if (code == -1001 || code == -2 || code == -3 || code == -300) {
            return "request_timeout";
        }
        if (code == -1 || code == -4 || code == -5 || code == -101 || code == -103 || code == -104) {
            return "phone_unavailable";
        }
        if (code == -102 || code == -200 || code == -201 || code == -202 || code == -400 || code >= 400) {
            return "service_unavailable";
        }
        return "network_error";
    }

    function invalidPairing(response) {
        if (!(response instanceof Dictionary) || response["error"] == null) {
            return false;
        }
        var code = response["error"]["code"];
        return code instanceof String && (
            code.equals("pairing_expired") ||
            code.equals("invalid_pairing") ||
            code.equals("invalid_device_secret")
        );
    }

    function successfulResponse(code, response) {
        return code == 200 && response instanceof Dictionary && response["ok"] == true;
    }

    function refresh() {
        if (!isPaired() || busy) {
            return;
        }
        disarm();
        if (!reconciliationRequired && queue.size() > 0) {
            flushQueue();
            return;
        }
        if (mode.equals("account")) {
            if (reconciliationRequired) {
                setMode("today");
            } else {
                status = "synced";
                requestUpdate();
            }
            return;
        }
        if (!reconciliationRequired) {
            status = "syncing";
        }
        busy = true;
        nextCursor = null;
        pendingViewMode = mode;
        pendingProjectId = projectId;
        pendingAppend = false;
        requestUpdate();
        if (mode.equals("lists")) {
            if (!relay.fetchProjects(null, method(:onProjects))) {
                onProjects(-1, null);
            }
        } else {
            var offset = Sys.getClockTime().timeZoneOffset / 60;
            if (!relay.fetchTasks(mode, projectId, offset, null, method(:onTasks))) {
                onTasks(-1, null);
            }
        }
    }

    function sameRequestContext(requestMode, requestProject) {
        if (!(requestMode instanceof String) || !mode.equals(requestMode)) {
            return false;
        }
        if (projectId == null) {
            return requestProject == null;
        }
        return requestProject instanceof String && projectId.equals(requestProject);
    }

    function loadNextPage() {
        if (busy || nextCursor == null || mode.equals("account")) {
            return;
        }
        busy = true;
        status = "loading_more";
        pendingViewMode = mode;
        pendingProjectId = projectId;
        pendingAppend = true;
        if (mode.equals("lists")) {
            if (!relay.fetchProjects(nextCursor, method(:onProjects))) {
                onProjects(-1, null);
            }
        } else {
            var offset = Sys.getClockTime().timeZoneOffset / 60;
            if (!relay.fetchTasks(mode, projectId, offset, nextCursor, method(:onTasks))) {
                onTasks(-1, null);
            }
        }
        requestUpdate();
    }

    function onProjects(code, response) {
        busy = false;
        var append = pendingAppend;
        pendingViewMode = null;
        pendingProjectId = null;
        pendingAppend = false;
        if (!mode.equals("lists")) {
            resumeAfterStaleResponse();
            return;
        }
        if (authorizationExpired(response)) {
            expireAuthorization();
            return;
        }
        if (cursorStale(response)) {
            nextCursor = null;
            refresh();
            return;
        }
        if (successfulResponse(code, response) && response["data"] instanceof Dictionary && response["data"]["projects"] instanceof Array) {
            var data = response["data"];
            var incoming = data["projects"];
            if (append && projects.size() + incoming.size() <= 60) {
                for (var index = 0; index < incoming.size(); index += 1) {
                    projects.add(incoming[index]);
                }
            } else {
                projects = incoming;
                selected = 0;
            }
            nextCursor = data["cursor"] instanceof String ? data["cursor"] : null;
            if (selected >= projects.size()) {
                selected = 0;
            }
            status = "synced";
        } else {
            status = "network_error";
        }
        requestUpdate();
    }

    function onTasks(code, response) {
        disarm();
        busy = false;
        var resumeQueue = false;
        var requestMode = pendingViewMode;
        var requestProject = pendingProjectId;
        var append = pendingAppend;
        pendingViewMode = null;
        pendingProjectId = null;
        pendingAppend = false;
        if (!sameRequestContext(requestMode, requestProject)) {
            resumeAfterStaleResponse();
            return;
        }
        if (authorizationExpired(response)) {
            expireAuthorization();
            return;
        }
        if (cursorStale(response)) {
            nextCursor = null;
            refresh();
            return;
        }
        if (successfulResponse(code, response) && response["data"] instanceof Dictionary && response["data"]["tasks"] instanceof Array) {
            var data = response["data"];
            var incoming = data["tasks"];
            if (append) {
                if (tasks.size() + incoming.size() <= 60) {
                    for (var index = 0; index < incoming.size(); index += 1) {
                        tasks.add(incoming[index]);
                    }
                } else {
                    tasks = incoming;
                    selected = 0;
                }
            } else {
                tasks = incoming;
                if (mode.equals("today")) {
                    store.setTasks(incoming);
                }
            }
            nextCursor = data["cursor"] instanceof String ? data["cursor"] : null;
            if (selected >= tasks.size()) {
                selected = 0;
            }
            status = reconciliationRequired ? "reconciled" : "synced";
            resumeQueue = reconciliationRequired && queue.size() > 0;
            reconciliationRequired = false;
        } else if (reconciliationRequired) {
            status = "completion_uncertain";
        } else if (tasks.size() > 0) {
            status = "offline_cache";
        } else {
            status = "network_error";
        }
        requestUpdate();
        if (resumeQueue) {
            flushQueue();
        }
    }

    function move(delta) {
        disarm();
        var items = activeItems();
        if (items.size() == 0) {
            return;
        }
        if (!busy && delta > 0 && selected == items.size() - 1 && nextCursor != null) {
            loadNextPage();
            return;
        }
        selected = (selected + delta + items.size()) % items.size();
        requestUpdate();
    }

    function select(index) {
        disarm();
        var items = activeItems();
        if (index < 0 || index >= items.size()) {
            return;
        }
        selected = index;
        requestUpdate();
    }

    function resumeAfterStaleResponse() {
        if (mode.equals("account")) {
            status = "synced";
            requestUpdate();
            return;
        }
        refresh();
    }

    // Switching scope never mutates a task. An ordinary in-flight response is discarded when it
    // returns and the newly visible scope is then fetched, so navigation never appears ignored.
    function setMode(name) {
        disarm();
        if (!isPaired() || mode.equals(name)) {
            return;
        }
        if (reconciliationRequired) {
            if (mode.equals("account") && !name.equals("account")) {
                mode = name;
                projectId = null;
                projectName = null;
                selected = 0;
                nextCursor = null;
                tasks = name.equals("today") ? store.getTasks() : [];
                status = "syncing_change";
                requestUpdate();
                refresh();
                return;
            }
            status = "syncing_change";
            requestUpdate();
            return;
        }
        var requestActive = busy;
        mode = name;
        projectId = null;
        projectName = null;
        selected = 0;
        nextCursor = null;
        tasks = name.equals("today") ? store.getTasks() : [];
        if (name.equals("account")) {
            status = "synced";
            requestUpdate();
        } else if (requestActive) {
            status = "switching_view";
            requestUpdate();
        } else {
            refresh();
        }
    }

    function primaryModeIndex(name) {
        if (name.equals("today")) {
            return 0;
        }
        if (name.equals("inbox")) {
            return 1;
        }
        if (name.equals("overdue")) {
            return 2;
        }
        if (name.equals("lists") || name.equals("project")) {
            return 3;
        }
        return -1;
    }

    function primaryModeAt(index) {
        if (index == 1) {
            return "inbox";
        }
        if (index == 2) {
            return "overdue";
        }
        if (index == 3) {
            return "lists";
        }
        return "today";
    }

    // Horizontal navigation cycles the four visible task destinations.
    // Account remains the fifth physical MENU destination, outside the daily-navigation band.
    function cyclePrimary(delta) {
        disarm();
        var index = primaryModeIndex(mode);
        if (index < 0) {
            setMode("today");
            return;
        }
        setMode(primaryModeAt((index + delta + 4) % 4));
    }

    function cycleMode() {
        disarm();
        if (mode.equals("today")) {
            setMode("inbox");
        } else if (mode.equals("inbox")) {
            setMode("overdue");
        } else if (mode.equals("overdue")) {
            setMode("lists");
        } else if (mode.equals("lists") || mode.equals("project")) {
            setMode("account");
        } else {
            setMode("today");
        }
    }

    function openSelectedProject() {
        if (projects.size() == 0) {
            refresh();
            return;
        }
        var project = projects[selected];
        if (project["id"] == null) {
            status = "network_error";
            requestUpdate();
            return;
        }
        mode = "project";
        projectId = project["id"];
        projectName = project["name"];
        selected = 0;
        nextCursor = null;
        tasks = [];
        status = "switching_view";
        requestUpdate();
        refresh();
    }

    function goBack() {
        if (disarm()) {
            return true;
        }
        if (mode.equals("project")) {
            mode = "lists";
            projectId = null;
            projectName = null;
            selected = 0;
            nextCursor = null;
            refresh();
            return true;
        }
        if (mode.equals("lists") || mode.equals("inbox") || mode.equals("overdue") || mode.equals("account")) {
            mode = "today";
            projectId = null;
            projectName = null;
            selected = 0;
            nextCursor = null;
            tasks = store.getTasks();
            refresh();
            return true;
        }
        return false;
    }

    function confirmSelectedCompletion() {
        var task = completionTask();
        confirmingCompletion = false;
        armedCompletionId = null;
        statusBeforeConfirm = null;
        if (task == null) {
            status = "task_changed";
            requestUpdate();
            refresh();
            return;
        }
        var mutationId = createMutationId();
        pendingTask = task;
        pendingMutationId = mutationId;
        if (queue.size() > 0) {
            if (queue.enqueueComplete(pendingTask, pendingMutationId)) {
                removeCompletedTask();
                status = "offline_queued";
            } else {
                status = "queue_full";
            }
            pendingTask = null;
            pendingMutationId = null;
            requestUpdate();
            return;
        }
        status = "completing";
        busy = true;
        requestUpdate();
        if (!relay.completeTask(task, mutationId, method(:onCompleted))) {
            onCompleted(-1, null);
        }
    }

    function createMutationId() {
        return "m-" + Time.now().value().format("%d") + "-" + Sys.getTimer().format("%d") + "-" + Math.rand().format("%d");
    }

    function canQueueCompletion(code, response) {
        if (response == null) {
            return code <= 0;
        }
        if (!(response instanceof Dictionary)) {
            return false;
        }
        if (response["ok"] == true || response["error"] == null) {
            return false;
        }
        var error = response["error"];
        var errorCode = error["code"];
        return errorCode instanceof String && !errorCode.equals("mutation_outcome_unknown") && error["retryable"] == true;
    }

    function authorizationExpired(response) {
        if (!(response instanceof Dictionary) || response["ok"] != false || response["error"] == null) {
            return false;
        }
        var code = response["error"]["code"];
        return code instanceof String && (code.equals("authorization_expired") || code.equals("unauthorized"));
    }

    function cursorStale(response) {
        if (!(response instanceof Dictionary) || response["ok"] != false || response["error"] == null) {
            return false;
        }
        var code = response["error"]["code"];
        return code instanceof String && code.equals("cursor_stale");
    }

    function requestRejected(response) {
        if (!(response instanceof Dictionary) || response["ok"] != false || response["error"] == null) {
            return false;
        }
        var code = response["error"]["code"];
        return code instanceof String && code.equals("request_rejected");
    }

    function confirmUnpair() {
        confirmingUnpair = false;
        statusBeforeConfirm = null;
        busy = true;
        status = "unpairing";
        requestUpdate();
        if (!relay.unpair(method(:onUnpaired))) {
            onUnpaired(-1, null);
        }
    }

    function onUnpaired(code, response) {
        busy = false;
        if (successfulResponse(code, response)) {
            finishUnpair();
        } else if (authorizationExpired(response)) {
            finishUnpair();
        } else {
            status = "unpair_failed";
            requestUpdate();
        }
    }

    function finishUnpair() {
        store.unpair();
        tasks = [];
        projects = [];
        mode = "today";
        projectId = null;
        projectName = null;
        selected = 0;
        verificationUrl = null;
        reconciliationRequired = false;
        statusBeforeConfirm = null;
        status = "unpaired";
        requestUpdate();
    }

    function expireAuthorization() {
        store.unpair();
        tasks = [];
        projects = [];
        projectName = null;
        confirmingCompletion = false;
        confirmingUnpair = false;
        statusBeforeConfirm = null;
        status = "authorization_expired";
        busy = false;
        requestUpdate();
    }

    function removeCompletedTask() {
        var completedId = pendingTask["id"];
        tasks.remove(pendingTask);
        nextCursor = null;
        var cachedToday = store.getTasks();
        for (var index = cachedToday.size() - 1; index >= 0; index -= 1) {
            var cachedId = cachedToday[index]["id"];
            if (cachedId instanceof String && completedId instanceof String && cachedId.equals(completedId)) {
                cachedToday.remove(cachedToday[index]);
            }
        }
        store.setTasks(cachedToday);
        if (selected >= tasks.size()) {
            selected = 0;
        }
    }

    function onCompleted(code, response) {
        busy = false;
        var refreshAfterCompletion = false;
        if (authorizationExpired(response)) {
            pendingTask = null;
            pendingMutationId = null;
            expireAuthorization();
            return;
        }
        if (successfulResponse(code, response)) {
            removeCompletedTask();
            status = "synced";
            refreshAfterCompletion = true;
        } else if (requestRejected(response)) {
            status = "change_rejected";
        } else if (canQueueCompletion(code, response) && queue.enqueueComplete(pendingTask, pendingMutationId)) {
            removeCompletedTask();
            status = "offline_queued";
        } else if (canQueueCompletion(code, response)) {
            status = "queue_full";
        } else {
            status = "completion_uncertain";
            reconciliationRequired = true;
        }
        pendingTask = null;
        pendingMutationId = null;
        requestUpdate();
        if (reconciliationRequired && !mode.equals("account")) {
            refresh();
        } else if (refreshAfterCompletion && !mode.equals("account")) {
            refresh();
        }
    }

    function flushQueue() {
        var mutation = queue.head();
        if (mutation == null) {
            refresh();
            return;
        }
        status = "syncing_change";
        busy = true;
        requestUpdate();
        if (!relay.replayComplete(mutation, method(:onQueueMutation))) {
            onQueueMutation(-1, null);
        }
    }

    function onQueueMutation(code, response) {
        busy = false;
        if (authorizationExpired(response)) {
            expireAuthorization();
            return;
        }
        if (successfulResponse(code, response)) {
            queue.removeHead();
            flushQueue();
        } else if (requestRejected(response)) {
            queue.removeHead();
            status = "change_rejected";
            reconciliationRequired = true;
            requestUpdate();
            refresh();
        } else if (!canQueueCompletion(code, response)) {
            queue.removeHead();
            status = "completion_uncertain";
            reconciliationRequired = true;
            requestUpdate();
            refresh();
        } else {
            status = "offline_queue_" + queue.size().format("%d");
            requestUpdate();
        }
    }
}
