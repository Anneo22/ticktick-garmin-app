import Toybox.Test;
import Toybox.Lang;

class PairedTestStore {
    var cachedTasks;

    function initialize() {
        cachedTasks = [];
    }

    function getRelayToken() {
        return "test-relay-token";
    }

    function getTasks() {
        return cachedTasks;
    }

    function setTasks(tasks) {
        cachedTasks = tasks;
    }
}

class NoopRelay {
    var lastView;
    var lastProjectId;
    var lastCursor;
    var lastAction;
    var replayCount;

    function initialize() {
        lastView = null;
        lastProjectId = null;
        lastCursor = null;
        lastAction = null;
        replayCount = 0;
    }

    function fetchTasks(view, projectId, utcOffsetMinutes, cursor, done) {
        lastView = view;
        lastProjectId = projectId;
        lastCursor = cursor;
        return true;
    }

    function fetchProjects(cursor, done) {
        lastView = "projects";
        lastCursor = cursor;
        return true;
    }

    function replayComplete(mutation, done) {
        lastAction = "replay";
        replayCount += 1;
        return true;
    }

    function completeTask(task, mutationId, done) {
        lastAction = "complete";
        return true;
    }

    function unpair(done) {
        lastAction = "unpair";
        return true;
    }

    function startPair(done) {
        lastAction = "startPair";
        return true;
    }

    function pollPair(deviceSecret, done) {
        lastAction = "pollPair";
        return true;
    }
}

class RejectingRelay extends NoopRelay {
    function initialize() {
        NoopRelay.initialize();
    }

    function fetchTasks(view, projectId, utcOffsetMinutes, cursor, done) {
        lastView = view;
        return false;
    }

    function fetchProjects(cursor, done) {
        lastView = "projects";
        return false;
    }

    function replayComplete(mutation, done) {
        lastAction = "replay";
        return false;
    }

    function completeTask(task, mutationId, done) {
        lastAction = "complete";
        return false;
    }

    function unpair(done) {
        lastAction = "unpair";
        return false;
    }
}

class DeferredCompletionRelay extends NoopRelay {
    var completionDone;
    var fetchCount;

    function initialize() {
        NoopRelay.initialize();
        completionDone = null;
        fetchCount = 0;
    }

    function fetchTasks(view, projectId, utcOffsetMinutes, cursor, done) {
        lastView = view;
        fetchCount += 1;
        return true;
    }

    function completeTask(task, mutationId, done) {
        lastAction = "complete";
        completionDone = done;
        return true;
    }

    function finish(code, response) {
        completionDone.invoke(code, response);
    }
}

class ReadyTaskController extends TaskController {
    function initialize() {
        TaskController.initialize();
    }

    function phoneReady() {
        return true;
    }
}

class OfflineTaskController extends TaskController {
    function initialize() {
        TaskController.initialize();
    }

    function phoneReady() {
        return false;
    }
}

class FailingPageController extends ReadyTaskController {
    function initialize() {
        ReadyTaskController.initialize();
    }

    function openVerificationPage() {
        return false;
    }
}

class RelayCallbackRecorder {
    var lastCode;

    function initialize() {
        lastCode = null;
    }

    function record(code, response) {
        lastCode = code;
    }
}

(:test)
function completionRequiresSecondSelect(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store = new PairedTestStore();
    controller.tasks = [{"id" => "task-1", "projectId" => "project-1", "title" => "Safe completion"}];
    controller.activate();
    Test.assert(controller.confirmingCompletion);
    Test.assert(!controller.busy);
    Test.assertEqual("confirm_complete", controller.status);
    controller.goBack();
    Test.assert(!controller.confirmingCompletion);
    return true;
}

(:test)
function uncertainMutationIsNeverQueued(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    var unknown = {"ok" => false, "error" => {"code" => "mutation_outcome_unknown", "retryable" => false}};
    var retryable = {"ok" => false, "error" => {"code" => "temporarily_unavailable", "retryable" => true}};
    Test.assert(!controller.canQueueCompletion(409, unknown));
    Test.assert(controller.canQueueCompletion(502, retryable));
    Test.assert(controller.canQueueCompletion(-1001, null));
    return true;
}

(:test)
function unpairRequiresSecondSelect(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    controller.mode = "account";
    Test.assertEqual("account", controller.mode);
    Test.assert(controller.isPaired());
    Test.assert(!controller.confirmingUnpair);
    Test.assert(!controller.reconciliationRequired);
    Test.assert(!controller.busy);
    controller.activate();
    Test.assert(controller.confirmingUnpair);
    Test.assert(!controller.busy);
    Test.assertEqual("confirm_unpair", controller.status);
    controller.goBack();
    Test.assert(!controller.confirmingUnpair);
    controller.store.unpair();
    return true;
}

(:test)
function confirmedUnpairClearsCredentialsCacheAndPendingQueue(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    controller.store.setPendingPair("device-secret", "ABC123", "https://example.invalid/pair");
    controller.store.setTasks([{"id" => "cached", "projectId" => "project-1", "title" => "Cached"}]);
    controller.tasks = controller.store.getTasks();
    controller.queue.enqueueComplete(controller.tasks[0], "pending-one");
    controller.mode = "account";
    controller.relay = new NoopRelay();
    controller.activate();
    Test.assert(controller.confirmingUnpair);
    Test.assertEqual(1, controller.queue.size());
    controller.activate();
    Test.assertEqual("unpair", controller.relay.lastAction);
    Test.assertEqual("unpairing", controller.status);
    Test.assert(controller.busy);
    controller.onUnpaired(200, {"ok" => true, "data" => {}});
    Test.assert(!controller.isPaired());
    Test.assertEqual(0, controller.store.getTasks().size());
    Test.assertEqual(0, controller.queue.size());
    Test.assert(controller.store.getDeviceSecret() == null);
    Test.assertEqual("unpaired", controller.status);
    return true;
}

(:test)
function successfulQueueDrainPreservesFifoThenRefreshes(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    controller.relay = new NoopRelay();
    controller.queue.enqueueComplete({"id" => "one", "projectId" => "project-1"}, "mutation-one");
    controller.queue.enqueueComplete({"id" => "two", "projectId" => "project-1"}, "mutation-two");
    controller.refresh();
    Test.assertEqual(1, controller.relay.replayCount);
    Test.assertEqual("mutation-one", controller.queue.head()["mutationId"]);
    controller.onQueueMutation(200, {"ok" => true, "data" => {"status" => "applied"}});
    Test.assertEqual(2, controller.relay.replayCount);
    Test.assertEqual("mutation-two", controller.queue.head()["mutationId"]);
    controller.onQueueMutation(200, {"ok" => true, "data" => {"status" => "applied"}});
    Test.assertEqual(0, controller.queue.size());
    Test.assertEqual("today", controller.relay.lastView);
    Test.assert(controller.busy);
    controller.store.unpair();
    return true;
}

(:test)
function retryableQueueHeadBlocksLaterMutations(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    controller.relay = new NoopRelay();
    controller.queue.enqueueComplete({"id" => "one", "projectId" => "project-1"}, "mutation-one");
    controller.queue.enqueueComplete({"id" => "two", "projectId" => "project-1"}, "mutation-two");
    controller.refresh();
    controller.onQueueMutation(502, {"ok" => false, "error" => {"code" => "temporarily_unavailable", "retryable" => true}});
    Test.assertEqual(1, controller.relay.replayCount);
    Test.assertEqual(2, controller.queue.size());
    Test.assertEqual("mutation-one", controller.queue.head()["mutationId"]);
    Test.assertEqual("offline_queue_2", controller.status);
    Test.assert(!controller.busy);
    controller.store.unpair();
    return true;
}

(:test)
function unknownQueueResultReconcilesBeforeLaterMutation(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    controller.relay = new NoopRelay();
    controller.queue.enqueueComplete({"id" => "one", "projectId" => "project-1"}, "mutation-one");
    controller.queue.enqueueComplete({"id" => "two", "projectId" => "project-1"}, "mutation-two");
    controller.refresh();
    controller.onQueueMutation(409, {"ok" => false, "error" => {"code" => "mutation_outcome_unknown", "retryable" => false}});
    Test.assertEqual(1, controller.relay.replayCount);
    Test.assertEqual(1, controller.queue.size());
    Test.assertEqual("mutation-two", controller.queue.head()["mutationId"]);
    Test.assert(controller.reconciliationRequired);
    Test.assertEqual("today", controller.relay.lastView);
    Test.assert(controller.busy);
    controller.onTasks(200, {"ok" => true, "data" => {"tasks" => []}});
    Test.assert(!controller.reconciliationRequired);
    Test.assertEqual(2, controller.relay.replayCount);
    Test.assertEqual(1, controller.queue.size());
    Test.assertEqual("mutation-two", controller.queue.head()["mutationId"]);
    Test.assert(controller.busy);
    controller.store.unpair();
    return true;
}

(:test)
function projectCompletionRemovesTaskFromTodayCache(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setTasks([
        {"id" => "task-1", "projectId" => "project-1", "title" => "Cached Today"},
        {"id" => "task-2", "projectId" => "project-1", "title" => "Keep Today"}
    ]);
    controller.mode = "project";
    Test.assertEqual("project", controller.mode);
    controller.pendingTask = {"id" => "task-1", "projectId" => "project-1", "title" => "Project copy"};
    controller.tasks = [controller.pendingTask];
    controller.removeCompletedTask();
    var cached = controller.store.getTasks();
    Test.assertEqual(1, cached.size());
    Test.assertEqual("task-2", cached[0]["id"]);
    controller.store.unpair();
    return true;
}

(:test)
function deletedPairingCanStartOver(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setPendingPair("device-secret", "ABC123", "https://example.invalid/pair");
    var parsedCode = "xinvalid_pairing".substring(1, 16);
    controller.onPairPolled(404, {"ok" => false, "error" => {"code" => parsedCode}});
    Test.assertEqual("pair_expired", controller.status);
    Test.assert(controller.store.getDeviceSecret() == null);
    Test.assert(controller.store.getUserCode() == null);
    controller.store.unpair();
    return true;
}

(:test)
function parsedPairedResponseStartsTodayRefresh(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setPendingPair("device-secret", "ABC123", "https://example.invalid/pair");
    controller.relay = new NoopRelay();
    var parsedStatus = "xpaired".substring(1, 7);
    controller.onPairPolled(200, {"ok" => true, "data" => {"status" => parsedStatus, "relayToken" => "device-secret"}});
    Test.assert(controller.isPaired());
    Test.assertEqual("today", controller.relay.lastView);
    Test.assert(controller.busy);
    controller.store.unpair();
    return true;
}

(:test)
function parsedAuthorizationErrorsAreRecognized(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    var expired = "xauthorization_expired".substring(1, 22);
    var rejected = "xrequest_rejected".substring(1, 17);
    Test.assert(controller.authorizationExpired({"ok" => false, "error" => {"code" => expired}}));
    Test.assert(controller.requestRejected({"ok" => false, "error" => {"code" => rejected}}));
    return true;
}

(:test)
function laterTaskPageAppendsAndKeepsCursor(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    controller.tasks = [{"id" => "task-1", "projectId" => "project-1", "title" => "First page"}];
    controller.pendingViewMode = "today";
    controller.pendingProjectId = null;
    controller.pendingAppend = true;
    controller.busy = true;
    var parsedCursor = "x20".substring(1, 3);
    controller.onTasks(200, {"ok" => true, "data" => {"tasks" => [{"id" => "task-2", "projectId" => "project-1", "title" => "Second page"}], "cursor" => parsedCursor}});
    Test.assertEqual(2, controller.tasks.size());
    Test.assertEqual("task-2", controller.tasks[1]["id"]);
    Test.assertEqual("20", controller.nextCursor);
    controller.store.unpair();
    return true;
}

(:test)
function laterProjectPageAppendsAndKeepsCursor(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    controller.mode = "lists";
    controller.projects = [{"id" => "project-1", "name" => "First"}];
    controller.pendingViewMode = "lists";
    controller.pendingProjectId = null;
    controller.pendingAppend = true;
    controller.busy = true;
    controller.onProjects(200, {"ok" => true, "data" => {"projects" => [{"id" => "project-2", "name" => "Second"}], "cursor" => "60"}});
    Test.assertEqual(2, controller.projects.size());
    Test.assertEqual("project-2", controller.projects[1]["id"]);
    Test.assertEqual("60", controller.nextCursor);
    controller.store.unpair();
    return true;
}

(:test)
function staleTaskCursorClearsAndRestartsFirstPage(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    controller.relay = new NoopRelay();
    controller.tasks = [{"id" => "task-1", "projectId" => "project-1", "title" => "Loaded"}];
    controller.nextCursor = "removed-anchor";
    controller.pendingViewMode = "today";
    controller.pendingProjectId = null;
    controller.pendingAppend = true;
    controller.busy = true;
    controller.onTasks(409, {"ok" => false, "error" => {"code" => "cursor_stale", "retryable" => true}});
    Test.assert(controller.nextCursor == null);
    Test.assertEqual("today", controller.relay.lastView);
    Test.assert(controller.relay.lastCursor == null);
    Test.assert(controller.busy);
    controller.store.unpair();
    return true;
}

(:test)
function staleProjectCursorClearsAndRestartsFirstPage(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    controller.relay = new NoopRelay();
    controller.mode = "lists";
    controller.projects = [{"id" => "project-1", "name" => "Loaded"}];
    controller.nextCursor = "removed-anchor";
    controller.pendingViewMode = "lists";
    controller.pendingProjectId = null;
    controller.pendingAppend = true;
    controller.busy = true;
    controller.onProjects(409, {"ok" => false, "error" => {"code" => "cursor_stale", "retryable" => true}});
    Test.assert(controller.nextCursor == null);
    Test.assertEqual("projects", controller.relay.lastView);
    Test.assert(controller.relay.lastCursor == null);
    Test.assert(controller.busy);
    controller.store.unpair();
    return true;
}

(:test)
function staleOverdueResponseCannotReplaceTodayCache(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    var cachedToday = [{"id" => "today-1", "projectId" => "project-1", "title" => "Keep Today"}];
    controller.store.setTasks(cachedToday);
    controller.tasks = [];
    controller.mode = "overdue";
    controller.pendingViewMode = "overdue";
    controller.pendingProjectId = null;
    controller.pendingAppend = false;
    controller.busy = true;
    controller.relay = new NoopRelay();
    controller.goBack();
    controller.onTasks(200, {"ok" => true, "data" => {"tasks" => [{"id" => "overdue-1", "projectId" => "project-1", "title" => "Do not cache"}]}});
    Test.assertEqual("today", controller.mode);
    Test.assertEqual("today", controller.relay.lastView);
    Test.assertEqual("today-1", controller.store.getTasks()[0]["id"]);
    Test.assertEqual("today-1", controller.tasks[0]["id"]);
    controller.store.unpair();
    return true;
}

(:test)
function inboxIsAFirstClassTaskScope(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store = new PairedTestStore();
    controller.relay = new NoopRelay();
    controller.setMode("inbox");
    Test.assertEqual("inbox", controller.mode);
    Test.assertEqual("inbox", controller.relay.lastView);
    Test.assert(controller.busy);
    return true;
}

(:test)
function visibleNavigationCyclesThreeScopesWithoutAccount(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store = new PairedTestStore();
    controller.relay = new NoopRelay();
    var modes = ["inbox", "lists", "today"];
    for (var index = 0; index < modes.size(); index += 1) {
        controller.busy = false;
        controller.cyclePrimary(1);
        Test.assertEqual(modes[index], controller.mode);
    }
    return true;
}

(:test)
function physicalMenuKeepsAccountAsFourthScope(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store = new PairedTestStore();
    controller.relay = new NoopRelay();
    var modes = ["inbox", "lists", "account", "today"];
    for (var index = 0; index < modes.size(); index += 1) {
        controller.busy = false;
        controller.cycleMode();
        Test.assertEqual(modes[index], controller.mode);
    }
    return true;
}

(:test)
function selectedListOpensTasksAndBackReturnsToLists(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store = new PairedTestStore();
    controller.relay = new NoopRelay();
    controller.mode = "lists";
    controller.projects = [
        {"id" => "project-1", "name" => "First"},
        {"id" => "project-2", "name" => "Second"}
    ];
    controller.selected = 1;
    controller.activate();
    Test.assertEqual("project", controller.mode);
    Test.assertEqual("project-2", controller.projectId);
    Test.assertEqual("project", controller.relay.lastView);
    Test.assertEqual("project-2", controller.relay.lastProjectId);
    controller.busy = false;
    Test.assert(controller.goBack());
    Test.assertEqual("lists", controller.mode);
    Test.assertEqual("projects", controller.relay.lastView);
    return true;
}

(:test)
function relayProjectPathCarriesOpaqueCursor(logger as Test.Logger) as Boolean {
    var client = new RelayClient(new PairedTestStore());
    var parsedView = "xproject".substring(1, 8);
    Test.assertEqual("/v1/tasks?view=project&projectId=project-1&cursor=task-opaque", client.taskPath(parsedView, "project-1", 0, "task-opaque"));
    return true;
}

(:test)
function fullCacheAndQueueAcceptMaximumTaskPage(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    var longTitle = "A task title sized to exercise the bounded relay response on the smallest supported watch without relying on a tiny fixture value.";
    var oldTasks = [];
    var newTasks = [];
    for (var index = 0; index < 20; index += 1) {
        oldTasks.add({"id" => "old-task-" + index.format("%d"), "projectId" => "project-with-a-long-identifier", "title" => longTitle, "dueDate" => "2026-08-05T20:00:00+0100", "status" => 0});
        newTasks.add({"id" => "new-task-" + index.format("%d"), "projectId" => "project-with-a-long-identifier", "title" => longTitle, "dueDate" => "2026-08-05T20:00:00+0100", "status" => 0});
    }
    controller.tasks = oldTasks;
    controller.store.setTasks(oldTasks);
    for (var queued = 0; queued < 8; queued += 1) {
        controller.queue.enqueueComplete(oldTasks[queued], "queued-mutation-" + queued.format("%d"));
    }
    controller.pendingViewMode = "today";
    controller.pendingProjectId = null;
    controller.pendingAppend = false;
    controller.busy = true;
    controller.onTasks(200, {"ok" => true, "data" => {"tasks" => newTasks}});
    Test.assertEqual(20, controller.tasks.size());
    Test.assertEqual(8, controller.queue.size());
    Test.assertEqual("new-task-19", controller.tasks[19]["id"]);
    controller.store.unpair();
    return true;
}

(:test)
function completionInvalidatesCursorAndKeepsCacheBounded(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    var firstTask = {"id" => "task-0", "projectId" => "project-1", "title" => "Task"};
    var cached = [firstTask];
    var loaded = [firstTask];
    for (var index = 1; index < 40; index += 1) {
        var task = {"id" => "task-" + index.format("%d"), "projectId" => "project-1", "title" => "Task"};
        loaded.add(task);
        if (index < 20) {
            cached.add(task);
        }
    }
    controller.store.setTasks(cached);
    controller.tasks = loaded;
    controller.pendingTask = firstTask;
    controller.pendingMutationId = "complete-first-page";
    controller.nextCursor = "40";
    controller.relay = new NoopRelay();
    controller.onCompleted(200, {"ok" => true, "data" => {"status" => "applied"}});
    Test.assert(controller.nextCursor == null);
    Test.assertEqual("today", controller.relay.lastView);
    Test.assertEqual(19, controller.store.getTasks().size());
    Test.assertEqual("task-1", controller.store.getTasks()[0]["id"]);
    controller.store.unpair();
    return true;
}

(:test)
function queuedHeadKeepsNewCompletionInFifo(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    controller.tasks = [{"id" => "new-task", "projectId" => "project-1", "title" => "Wait behind queue"}];
    controller.queue.enqueueComplete({"id" => "queued-task", "projectId" => "project-1", "title" => "First"}, "queued-first");
    controller.relay = new NoopRelay();
    controller.activate();
    Test.assert(controller.confirmingCompletion);
    controller.activate();
    Test.assert(controller.relay.lastAction == null);
    Test.assertEqual(2, controller.queue.size());
    Test.assertEqual("queued-first", controller.queue.head()["mutationId"]);
    Test.assertEqual(0, controller.tasks.size());
    Test.assert(!controller.busy);
    controller.store.unpair();
    return true;
}

(:test)
function mutationIdIsOpaqueAndBounded(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    var id = controller.createMutationId();
    Test.assert(id.length() <= 96);
    Test.assert(id.find("task-") == null);
    Test.assert(!id.equals(controller.createMutationId()));
    return true;
}

(:test)
function directSelectionIsBoundedAndDoesNotCompleteImmediately(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store = new PairedTestStore();
    controller.tasks = [
        {"id" => "task-1", "projectId" => "project-1", "title" => "First"},
        {"id" => "task-2", "projectId" => "project-1", "title" => "Second"}
    ];
    controller.select(1);
    Test.assertEqual(1, controller.selected);
    Test.assert(!controller.confirmingCompletion);
    controller.select(-1);
    Test.assertEqual(1, controller.selected);
    controller.select(2);
    Test.assertEqual(1, controller.selected);
    return true;
}

(:test)
function pairingTapUsesTheWholeScreen(logger as Test.Logger) as Boolean {
    var controller = new ReadyTaskController();
    controller.store.unpair();
    controller.relay = new NoopRelay();
    var view = new TaskListView(controller);
    view.screenWidth = 454;
    view.screenHeight = 454;
    Test.assert(view.handleTap([1, 1]));
    Test.assertEqual("startPair", controller.relay.lastAction);
    Test.assert(controller.busy);
    controller.store.unpair();
    return true;
}

(:test)
function unavailablePhoneNeverEntersBusyPairing(logger as Test.Logger) as Boolean {
    var controller = new OfflineTaskController();
    controller.store.unpair();
    controller.relay = new NoopRelay();
    controller.beginOrPollPair();
    Test.assert(!controller.busy);
    Test.assertEqual("phone_unavailable", controller.status);
    Test.assert(controller.relay.lastAction == null);
    return true;
}

(:test)
function busyControllerKeepsSafeNavigationResponsive(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store = new PairedTestStore();
    controller.tasks = [
        {"id" => "task-1", "projectId" => "project-1", "title" => "First"},
        {"id" => "task-2", "projectId" => "project-1", "title" => "Second"}
    ];
    controller.busy = true;
    controller.move(1);
    controller.select(1);
    Test.assertEqual(1, controller.selected);
    return true;
}

(:test)
function completionFinishingOnAccountNeverFetchesAnAccountTaskList(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store = new PairedTestStore();
    controller.tasks = [{"id" => "task-1", "projectId" => "project-1", "title" => "Complete me"}];
    controller.queue.store.setQueue([]);
    var relay = new DeferredCompletionRelay();
    controller.relay = relay;
    controller.activate();
    controller.activate();
    Test.assert(controller.busy);
    controller.setMode("account");
    relay.finish(200, {"ok" => true, "data" => {}});
    Test.assertEqual("account", controller.mode);
    Test.assertEqual(0, relay.fetchCount);
    Test.assert(!controller.busy);
    Test.assertEqual("synced", controller.status);
    return true;
}

(:test)
function uncertainCompletionCanLeaveAccountToReconcile(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store = new PairedTestStore();
    controller.tasks = [{"id" => "task-1", "projectId" => "project-1", "title" => "Complete me"}];
    controller.queue.store.setQueue([]);
    var relay = new DeferredCompletionRelay();
    controller.relay = relay;
    controller.activate();
    controller.activate();
    controller.setMode("account");
    relay.finish(200, {"ok" => false, "error" => {"code" => "mutation_outcome_unknown"}});
    Test.assert(controller.reconciliationRequired);
    Test.assertEqual(0, relay.fetchCount);
    controller.activate();
    Test.assertEqual("today", controller.mode);
    Test.assertEqual(1, relay.fetchCount);
    Test.assert(controller.busy);
    return true;
}

(:test)
function refreshCancelsArmedCompletionBeforeTasksCanReorder(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store = new PairedTestStore();
    controller.tasks = [
        {"id" => "task-a", "projectId" => "project-1", "title" => "Task A"},
        {"id" => "task-b", "projectId" => "project-1", "title" => "Task B"}
    ];
    controller.queue.store.setQueue([]);
    controller.relay = new NoopRelay();
    controller.armCompletion();
    Test.assert(controller.confirmingCompletion);
    var view = new TaskListView(controller);
    view.onShow();
    Test.assert(!controller.confirmingCompletion);
    controller.onTasks(200, {"ok" => true, "data" => {"tasks" => [
        {"id" => "task-b", "projectId" => "project-1", "title" => "Task B"},
        {"id" => "task-a", "projectId" => "project-1", "title" => "Task A"}
    ]}});
    Test.assert(!controller.confirmingCompletion);
    Test.assert(controller.relay.lastAction == null);
    return true;
}

(:test)
function refreshToEmptyCannotRenderOrCompleteAnArmedTask(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store = new PairedTestStore();
    controller.tasks = [{"id" => "task-a", "projectId" => "project-1", "title" => "Task A"}];
    controller.queue.store.setQueue([]);
    controller.relay = new NoopRelay();
    controller.armCompletion();
    Test.assert(controller.confirmingCompletion);
    controller.refresh();
    controller.onTasks(200, {"ok" => true, "data" => {"tasks" => []}});
    Test.assertEqual(0, controller.tasks.size());
    Test.assert(!controller.confirmingCompletion);
    Test.assert(controller.completionTask() == null);
    Test.assert(controller.relay.lastAction == null);
    return true;
}

(:test)
function relayCompletionReleasesOwnedRequestBeforeCallback(logger as Test.Logger) as Boolean {
    var client = new RelayClient(new PairedTestStore());
    var recorder = new RelayCallbackRecorder();
    client.activeRequest = new RelayRequest(null, 1);
    client.activeCallback = recorder.method(:record);
    client.finishRequest(200, {"ok" => true});
    Test.assert(client.activeRequest == null);
    Test.assert(client.activeCallback == null);
    Test.assertEqual(200, recorder.lastCode);
    return true;
}

(:test)
function pairingTimeoutUnlocksRetry(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.busy = true;
    controller.status = "pairing";
    controller.onPairStarted(-1001, null);
    Test.assert(!controller.busy);
    Test.assertEqual("request_timeout", controller.status);
    return true;
}

(:test)
function pairingFailuresKeepActionableCause(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.busy = true;
    controller.onPairStarted(-104, null);
    Test.assertEqual("phone_unavailable", controller.status);
    controller.busy = true;
    controller.onPairStarted(-300, null);
    Test.assertEqual("request_timeout", controller.status);
    controller.busy = true;
    controller.onPairStarted(503, {"ok" => false});
    Test.assertEqual("service_unavailable", controller.status);
    return true;
}

(:test)
function pairingUxUsesCompactSpecificLabels(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    var view = new TaskListView(controller);
    Test.assertEqual("START PAIRING", view.pairActionLabel(null));
    controller.busy = true;
    Test.assertEqual("CONNECTING", view.pairActionLabel(null));
    Test.assertEqual("CHECKING", view.pairActionLabel("ABC123"));
    controller.busy = false;
    controller.status = "phone_unavailable";
    Test.assertEqual("TRY AGAIN", view.pairActionLabel(null));
    Test.assertEqual("Open Garmin Connect", view.statusLabel());
    controller.status = "service_unavailable";
    Test.assertEqual("Setup unavailable", view.statusLabel());
    return true;
}

(:test)
function pendingPairingRestoresHonestStatus(logger as Test.Logger) as Boolean {
    var seed = new LocalStore();
    seed.unpair();
    seed.setPendingPair("device-secret", "ABC123", "https://example.invalid/pair");
    var controller = new TaskController();
    Test.assertEqual("pair_pending", controller.status);
    Test.assertEqual("ABC123", controller.store.getUserCode());
    controller.store.unpair();
    return true;
}

(:test)
function stringSuccessBodyDoesNotCrashCallbacks(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    var cachedTasks = [{"id" => "cached", "projectId" => "project-1", "title" => "Cached"}];
    controller.store.setTasks(cachedTasks);
    controller.tasks = cachedTasks;
    controller.pendingViewMode = "today";
    controller.pendingProjectId = null;
    controller.pendingAppend = false;
    controller.busy = true;
    controller.onTasks(200, "<html>not json</html>");
    Test.assertEqual("offline_cache", controller.status);
    Test.assertEqual(1, controller.tasks.size());
    Test.assertEqual("cached", controller.store.getTasks()[0]["id"]);
    controller.store.unpair();
    return true;
}

(:test)
function maximumPaginationWindowReplacesWithoutOverflow(logger as Test.Logger) as Boolean {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store.setRelayToken("test-relay-token");
    var longTitle = "A task title sized to exercise a full pagination window and incoming page on the smallest supported watch memory budget.";
    var loaded = [];
    var incoming = [];
    var cached = [];
    for (var index = 0; index < 60; index += 1) {
        var task = {"id" => "loaded-" + index.format("%d"), "projectId" => "project-with-a-long-identifier", "title" => longTitle, "dueDate" => "2026-08-05T20:00:00+0100", "status" => 0};
        loaded.add(task);
        if (index < 20) {
            cached.add(task);
        }
    }
    for (var next = 0; next < 20; next += 1) {
        incoming.add({"id" => "incoming-" + next.format("%d"), "projectId" => "project-with-a-long-identifier", "title" => longTitle, "dueDate" => "2026-08-05T20:00:00+0100", "status" => 0});
    }
    controller.tasks = loaded;
    controller.store.setTasks(cached);
    for (var queued = 0; queued < 8; queued += 1) {
        controller.queue.enqueueComplete({"id" => "queued-" + queued.format("%d"), "projectId" => "project-with-a-long-identifier"}, "peak-queue-" + queued.format("%d"));
    }
    controller.pendingViewMode = "today";
    controller.pendingProjectId = null;
    controller.pendingAppend = true;
    controller.busy = true;
    controller.onTasks(200, {"ok" => true, "data" => {"tasks" => incoming, "cursor" => "80"}});
    Test.assertEqual(20, controller.tasks.size());
    Test.assertEqual("incoming-0", controller.tasks[0]["id"]);
    Test.assertEqual(20, controller.store.getTasks().size());
    Test.assertEqual(8, controller.queue.size());
    Test.assertEqual("80", controller.nextCursor);
    controller.store.unpair();
    return true;
}

(:test)
function rejectedRelayStartsAlwaysUnlockController(logger as Test.Logger) as Boolean {
    var task = {"id" => "reject-task", "projectId" => "project-1", "title" => "Reject safely"};

    var refreshController = new TaskController();
    refreshController.store = new PairedTestStore();
    refreshController.tasks = [task];
    refreshController.relay = new RejectingRelay();
    refreshController.refresh();
    Test.assert(!refreshController.busy);
    Test.assertEqual("offline_cache", refreshController.status);

    refreshController.nextCursor = "next";
    refreshController.loadNextPage();
    Test.assert(!refreshController.busy);
    Test.assertEqual("offline_cache", refreshController.status);

    var completionController = new TaskController();
    completionController.store = new PairedTestStore();
    completionController.tasks = [task];
    completionController.queue.store.setQueue([]);
    completionController.relay = new RejectingRelay();
    completionController.activate();
    completionController.activate();
    Test.assert(!completionController.busy);
    Test.assertEqual("offline_queued", completionController.status);

    var unpairController = new TaskController();
    unpairController.store = new PairedTestStore();
    unpairController.mode = "account";
    unpairController.relay = new RejectingRelay();
    unpairController.activate();
    unpairController.activate();
    Test.assert(!unpairController.busy);
    Test.assertEqual("unpair_failed", unpairController.status);

    var queueController = new TaskController();
    queueController.store = new PairedTestStore();
    queueController.queue.store.setQueue([]);
    queueController.queue.enqueueComplete(task, "queued-rejection");
    queueController.relay = new RejectingRelay();
    queueController.flushQueue();
    Test.assert(!queueController.busy);
    Test.assertEqual("offline_queue_1", queueController.status);
    queueController.queue.store.setQueue([]);
    return true;
}

(:test)
function phonePageFailureNeverPreventsPairPolling(logger as Test.Logger) as Boolean {
    var controller = new FailingPageController();
    controller.store.unpair();
    controller.store.setPendingPair("device-secret", "ABC123", "https://example.invalid/pair");
    controller.verificationUrl = controller.store.getVerificationUrl();
    controller.relay = new NoopRelay();
    controller.beginOrPollPair();
    Test.assertEqual("pollPair", controller.relay.lastAction);
    Test.assert(controller.busy);
    controller.onPairPolled(200, {"ok" => true, "data" => {"status" => "pending"}});
    Test.assert(!controller.busy);
    Test.assertEqual("pair_pending", controller.status);

    controller.busy = true;
    controller.onPairStarted(200, {"ok" => true, "data" => {"deviceSecret" => "new-secret", "userCode" => "XYZ234", "verificationUrl" => "https://example.invalid/pair"}});
    Test.assert(!controller.busy);
    Test.assertEqual("phone_unavailable", controller.status);
    controller.store.unpair();
    return true;
}
