import Toybox.Test;
import Toybox.Lang;

// Regression cover for the direction contract in TaskListView (concept seed d39802f1):
// route stops, isolated navigation, deliberate two-step completion, one geometry.
// Font heights are supplied directly so layout() is exercised without a device context,
// which is the same entry point onUpdate() uses before it draws.
const FENIX_SIZE = 454;
const FENIX_TITLE_HEIGHT = 29;
const FENIX_BODY_HEIGHT = 21;
const COMPACT_SIZE = 176;

function routeController(taskCount) {
    var controller = new TaskController();
    controller.store.unpair();
    controller.store = new PairedTestStore();
    var tasks = [];
    for (var index = 0; index < taskCount; index += 1) {
        tasks.add({"id" => "task-" + index.format("%d"), "projectId" => "project-1", "title" => "Stop " + index.format("%d")});
    }
    controller.tasks = tasks;
    controller.relay = new NoopRelay();
    return controller;
}

function routeView(controller, size) {
    var view = new TaskListView(controller);
    view.layout(size, size, size == COMPACT_SIZE ? FENIX_BODY_HEIGHT : FENIX_TITLE_HEIGHT, FENIX_BODY_HEIGHT);
    return view;
}

function centerOf(bounds) {
    return [bounds[0] + bounds[2] / 2, bounds[1] + bounds[3] / 2];
}

function boundsForIndex(list, index) {
    for (var entry = 0; entry < list.size(); entry += 1) {
        if (list[entry][4] == index) {
            return list[entry];
        }
    }
    return null;
}

function overlaps(first, second) {
    return first[0] < second[0] + second[2] && second[0] < first[0] + first[2] &&
        first[1] < second[1] + second[3] && second[1] < first[1] + first[3];
}

(:test)
function rowTapSelectsOnlyAndNeverArms(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    var view = routeView(controller, FENIX_SIZE);
    var target = boundsForIndex(view.rowBounds, 2);
    Test.assert(target != null);
    Test.assert(view.handleTap([target[0] + target[2] - 4, centerOf(target)[1]]));
    Test.assertEqual(2, controller.selected);
    Test.assert(!controller.confirmingCompletion);
    Test.assert(controller.relay.lastAction == null);
    return true;
}

(:test)
function selectedRowRetapNeverArmsOrCompletes(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    controller.selected = 1;
    var view = routeView(controller, FENIX_SIZE);
    var target = boundsForIndex(view.rowBounds, 1);
    var point = [target[0] + target[2] - 4, centerOf(target)[1]];
    Test.assert(view.handleTap(point));
    Test.assert(view.handleTap(point));
    Test.assert(view.handleTap(point));
    Test.assertEqual(1, controller.selected);
    Test.assert(!controller.confirmingCompletion);
    Test.assert(controller.relay.lastAction == null);
    return true;
}

(:test)
function completionNodeArmsOnlyTheSelectedStop(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    var view = routeView(controller, FENIX_SIZE);
    var other = boundsForIndex(view.nodeBounds, 2);
    Test.assert(view.handleTap(centerOf(other)));
    Test.assertEqual(2, controller.selected);
    Test.assert(!controller.confirmingCompletion);

    view.layout(FENIX_SIZE, FENIX_SIZE, FENIX_TITLE_HEIGHT, FENIX_BODY_HEIGHT);
    var selectedNode = boundsForIndex(view.nodeBounds, 2);
    Test.assert(view.handleTap(centerOf(selectedNode)));
    Test.assert(controller.confirmingCompletion);
    Test.assert(controller.relay.lastAction == null);
    return true;
}

(:test)
function armedScreenExposesOnlyTheConfirmTarget(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    controller.armCompletion();
    Test.assert(controller.confirmingCompletion);
    var view = routeView(controller, FENIX_SIZE);
    Test.assertEqual(0, view.rowBounds.size());
    Test.assertEqual(0, view.nodeBounds.size());
    Test.assertEqual(0, view.navBounds.size());
    Test.assert(view.actionBounds != null);

    Test.assert(view.handleTap([FENIX_SIZE / 2, view.actionBounds[1] - 40]));
    Test.assert(controller.confirmingCompletion);
    Test.assert(controller.relay.lastAction == null);

    Test.assert(view.handleTap(centerOf(view.actionBounds)));
    Test.assertEqual("complete", controller.relay.lastAction);
    Test.assert(!controller.confirmingCompletion);
    return true;
}

(:test)
function emptySpaceTapNeverArmsOrCompletes(logger as Test.Logger) as Boolean {
    var controller = routeController(2);
    var view = routeView(controller, FENIX_SIZE);
    var lastRow = view.rowBounds[view.rowBounds.size() - 1];
    var gapY = lastRow[1] + lastRow[3] + 4;
    Test.assert(gapY < view.navBounds[0][1]);
    Test.assert(view.handleTap([FENIX_SIZE / 2, gapY]));
    Test.assert(view.handleTap([2, 2]));
    Test.assertEqual(0, controller.selected);
    Test.assert(!controller.confirmingCompletion);
    Test.assert(controller.relay.lastAction == null);
    return true;
}

(:test)
function accountReconciliationShowsAndRunsOnlySync(logger as Test.Logger) as Boolean {
    var controller = routeController(1);
    controller.mode = "account";
    controller.reconciliationRequired = true;
    var view = routeView(controller, FENIX_SIZE);
    Test.assertEqual("reconcile", view.actionKind);
    Test.assert(view.handleTap(centerOf(view.actionBounds)));
    Test.assertEqual("today", controller.mode);
    Test.assertEqual("today", controller.relay.lastView);
    Test.assert(!controller.confirmingUnpair);
    return true;
}

(:test)
function navigationTapSwitchesScopeAndDisarms(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    var view = routeView(controller, FENIX_SIZE);
    Test.assertEqual("today", view.navBounds[0][4]);
    Test.assertEqual("overdue", view.navBounds[1][4]);
    Test.assertEqual("projects", view.navBounds[2][4]);
    Test.assert(view.handleTap(centerOf(view.navBounds[1])));
    Test.assertEqual("overdue", controller.mode);
    Test.assert(!controller.confirmingCompletion);
    Test.assertEqual("overdue", controller.relay.lastView);
    return true;
}

(:test)
function navigationBoundsNeverOverlapAStop(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    var view = routeView(controller, FENIX_SIZE);
    for (var nav = 0; nav < view.navBounds.size(); nav += 1) {
        for (var row = 0; row < view.rowBounds.size(); row += 1) {
            Test.assert(!overlaps(view.navBounds[nav], view.rowBounds[row]));
        }
        for (var node = 0; node < view.nodeBounds.size(); node += 1) {
            Test.assert(!overlaps(view.navBounds[nav], view.nodeBounds[node]));
        }
    }
    for (var entry = 0; entry < view.rowBounds.size(); entry += 1) {
        Test.assert(!overlaps(view.rowBounds[entry], view.nodeBounds[entry]));
    }
    return true;
}

(:test)
function navigationDisarmsEvenWhileBusy(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    var idle = controller.status;
    controller.armCompletion();
    Test.assert(controller.confirmingCompletion);
    controller.busy = true;
    controller.cycleMode();
    Test.assert(!controller.confirmingCompletion);
    Test.assertEqual("overdue", controller.mode);
    Test.assertEqual("switching_view", controller.status);

    controller.armCompletion();
    Test.assert(!controller.confirmingCompletion);
    controller.busy = false;
    controller.mode = "today";
    controller.tasks = [{"id" => "restored", "projectId" => "project-1", "title" => "Restored"}];
    controller.status = idle;
    controller.armCompletion();
    Test.assert(controller.confirmingCompletion);
    Test.assert(controller.goBack());
    Test.assert(!controller.confirmingCompletion);
    Test.assertEqual(idle, controller.status);
    return true;
}

(:test)
function startSelectRemainsTwoStepAndTouchAddsNoShortcut(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    controller.activate();
    Test.assert(controller.confirmingCompletion);
    Test.assert(controller.relay.lastAction == null);
    controller.activate();
    Test.assertEqual("complete", controller.relay.lastAction);
    return true;
}

(:test)
function drawnBoundsAreTheHitTestBounds(logger as Test.Logger) as Boolean {
    var controller = routeController(6);
    controller.selected = 3;
    var view = routeView(controller, FENIX_SIZE);
    Test.assertEqual(3, view.rowBounds.size());
    Test.assertEqual(3, view.nodeBounds.size());
    for (var row = 0; row < view.rowBounds.size(); row += 1) {
        var bounds = view.rowBounds[row];
        Test.assert(bounds[2] > 0 && bounds[3] > 0);
        view.handleTap([bounds[0] + bounds[2] - 4, centerOf(bounds)[1]]);
        Test.assertEqual(bounds[4], controller.selected);
        Test.assert(!controller.confirmingCompletion);
    }
    var below = view.rowBounds[view.rowBounds.size() - 1];
    Test.assert(!view.contains(below, FENIX_SIZE / 2, below[1] + below[3] + 1));
    return true;
}

(:test)
function compactStaysButtonFirstWithoutTouchCompletion(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    var view = routeView(controller, COMPACT_SIZE);
    Test.assertEqual(3, view.rowBounds.size());
    Test.assertEqual(0, view.nodeBounds.size());
    Test.assertEqual(1, view.navBounds.size());
    Test.assertEqual("cycle", view.navBounds[0][4]);
    var target = view.rowBounds[2];
    Test.assert(view.handleTap(centerOf(target)));
    Test.assertEqual(2, controller.selected);
    Test.assert(!controller.confirmingCompletion);
    Test.assert(view.handleTap(centerOf(target)));
    Test.assert(!controller.confirmingCompletion);
    controller.activate();
    Test.assert(controller.confirmingCompletion);
    return true;
}

(:test)
function emptyAndLoadingViewsKeepSafeNavigation(logger as Test.Logger) as Boolean {
    var controller = routeController(0);
    var view = routeView(controller, FENIX_SIZE);
    Test.assertEqual(3, view.navBounds.size());
    Test.assert(view.actionBounds != null);
    Test.assert(view.handleTap(centerOf(view.navBounds[2])));
    Test.assertEqual("projects", controller.mode);

    controller.busy = true;
    view.layout(FENIX_SIZE, FENIX_SIZE, FENIX_TITLE_HEIGHT, FENIX_BODY_HEIGHT);
    Test.assertEqual(3, view.navBounds.size());
    Test.assert(view.actionBounds == null);
    return true;
}

(:test)
function busySelectionStillMovesAndAlwaysDisarms(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    controller.busy = true;
    controller.confirmingCompletion = true;
    controller.move(1);
    Test.assertEqual(1, controller.selected);
    Test.assert(!controller.confirmingCompletion);
    controller.select(2);
    Test.assertEqual(2, controller.selected);
    Test.assert(!controller.confirmingCompletion);
    return true;
}

(:test)
function compactEmptyAndLoadingExposeVisibleNavigation(logger as Test.Logger) as Boolean {
    var controller = routeController(0);
    var view = routeView(controller, COMPACT_SIZE);
    Test.assertEqual(1, view.navBounds.size());
    Test.assertEqual("cycle", view.navBounds[0][4]);
    Test.assert(view.actionBounds != null);
    Test.assert(!overlaps(view.actionBounds, view.navBounds[0]));
    controller.busy = true;
    view.layout(COMPACT_SIZE, COMPACT_SIZE, FENIX_BODY_HEIGHT, FENIX_BODY_HEIGHT);
    Test.assertEqual(1, view.navBounds.size());
    Test.assert(view.actionBounds == null);
    return true;
}

(:test)
function staleActionBoundsNeverBecomeTaskCompletion(logger as Test.Logger) as Boolean {
    var controller = routeController(0);
    var view = routeView(controller, FENIX_SIZE);
    var staleRefresh = centerOf(view.actionBounds);
    controller.tasks = [{"id" => "late-task", "projectId" => "project-1", "title" => "Arrived after layout"}];
    Test.assert(view.handleTap(staleRefresh));
    Test.assert(view.handleTap(staleRefresh));
    Test.assert(!controller.confirmingCompletion);
    Test.assert(controller.relay.lastAction == null);
    return true;
}

(:test)
function rowEdgesNeverEnterTheCompletionGutter(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    controller.selected = 1;
    var view = routeView(controller, FENIX_SIZE);
    var row = boundsForIndex(view.rowBounds, 1);
    var points = [
        [row[0] + 1, centerOf(row)[1]],
        centerOf(row),
        [row[0] + row[2] - 1, centerOf(row)[1]]
    ];
    for (var point = 0; point < points.size(); point += 1) {
        Test.assert(view.handleTap(points[point]));
        Test.assert(!controller.confirmingCompletion);
    }
    return true;
}

(:test)
function delegateMenuCannotSkipConfirmation(logger as Test.Logger) as Boolean {
    var controller = routeController(3);
    var view = routeView(controller, FENIX_SIZE);
    var delegate = new TaskListDelegate(controller, view);
    controller.armCompletion();
    Test.assert(controller.confirmingCompletion);
    Test.assert(delegate.onMenu());
    Test.assert(!controller.confirmingCompletion);
    Test.assertEqual("overdue", controller.mode);

    return true;
}

(:test)
function representativeScreenFamiliesKeepGeometrySeparated(logger as Test.Logger) as Boolean {
    var sizes = [176, 208, 218, 240, 260, 390, 454];
    for (var sizeIndex = 0; sizeIndex < sizes.size(); sizeIndex += 1) {
        var size = sizes[sizeIndex];
        var controller = routeController(4);
        var view = new TaskListView(controller);
        view.layout(size, size, size <= 240 ? 21 : 29, size <= 240 ? 16 : 21);
        for (var row = 0; row < view.rowBounds.size(); row += 1) {
            var bounds = view.rowBounds[row];
            Test.assert(bounds[0] >= 0 && bounds[1] >= 0);
            Test.assert(bounds[0] + bounds[2] <= size);
            Test.assert(bounds[1] + bounds[3] <= view.navBounds[0][1]);
            if (view.nodeBounds.size() > 0) {
                Test.assert(!overlaps(bounds, view.nodeBounds[row]));
                Test.assert(!overlaps(view.nodeBounds[row], view.navBounds[0]));
            }
        }
    }
    return true;
}

(:test)
function semiroundCompactGeometryKeepsEveryTargetVisible(logger as Test.Logger) as Boolean {
    var controller = routeController(4);
    var view = new TaskListView(controller);
    view.layout(215, 180, 21, 16);
    Test.assertEqual(1, view.navBounds.size());
    for (var row = 0; row < view.rowBounds.size(); row += 1) {
        var bounds = view.rowBounds[row];
        Test.assert(bounds[0] >= 0 && bounds[1] >= 0);
        Test.assert(bounds[0] + bounds[2] <= 215);
        Test.assert(bounds[1] + bounds[3] <= view.navBounds[0][1]);
    }
    return true;
}

(:test)
function projectRowsOpenOnlyThroughTheirOwnNode(logger as Test.Logger) as Boolean {
    var controller = routeController(0);
    controller.mode = "projects";
    controller.projects = [
        {"id" => "project-1", "name" => "First"},
        {"id" => "project-2", "name" => "Second"}
    ];
    var view = routeView(controller, FENIX_SIZE);
    var row = boundsForIndex(view.rowBounds, 1);
    Test.assert(view.handleTap([row[0] + row[2] - 4, centerOf(row)[1]]));
    Test.assertEqual(1, controller.selected);
    Test.assertEqual("projects", controller.mode);

    view.layout(FENIX_SIZE, FENIX_SIZE, FENIX_TITLE_HEIGHT, FENIX_BODY_HEIGHT);
    Test.assert(view.handleTap(centerOf(boundsForIndex(view.nodeBounds, 1))));
    Test.assertEqual("project", controller.mode);
    Test.assertEqual("project-2", controller.projectId);
    Test.assert(!controller.confirmingCompletion);
    return true;
}
