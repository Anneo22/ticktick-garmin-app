using Toybox.Application as App;

// Simulator-only visual fixture. It is excluded from production builds and contains no account data.
class VisualQaController extends TaskController {
    var qaTasks;

    function initialize() {
        TaskController.initialize();
        qaTasks = [
            {
                "id" => "qa-task-1",
                "projectId" => "qa-list-1",
                "title" => "Review launch plan",
                "dueDate" => "2026-08-10T18:30:00+0100",
                "isAllDay" => false
            },
            {
                "id" => "qa-task-2",
                "projectId" => "qa-list-1",
                "title" => "Reply to notes",
                "dueDate" => "2026-08-10T20:00:00+0100",
                "isAllDay" => false
            },
            {
                "id" => "qa-task-3",
                "projectId" => "qa-list-2",
                "title" => "Plan the week",
                "dueDate" => "2026-08-10",
                "isAllDay" => true
            }
        ];
        tasks = qaTasks;
        projects = [
            {"id" => "qa-list-1", "name" => "Garmin launch"},
            {"id" => "qa-list-2", "name" => "Personal"},
            {"id" => "qa-list-3", "name" => "Training and travel"}
        ];
        mode = "today";
        status = "synced";
        selected = 0;
        busy = false;
    }

    function isPaired() {
        return true;
    }

    function refresh() {
        busy = false;
        status = "synced";
        requestUpdate();
    }

    function setMode(name) {
        disarm();
        mode = name;
        projectId = null;
        projectName = null;
        tasks = qaTasks;
        selected = 0;
        status = "synced";
        requestUpdate();
    }

    function openSelectedProject() {
        if (projects.size() == 0) {
            return;
        }
        var project = projects[selected];
        mode = "project";
        projectId = project["id"];
        projectName = project["name"];
        tasks = qaTasks;
        selected = 0;
        status = "synced";
        requestUpdate();
    }

    function goBack() {
        if (disarm()) {
            return true;
        }
        setMode(mode.equals("project") ? "lists" : "today");
        return true;
    }
}

class VisualQaApp extends App.AppBase {
    var controller;

    function initialize() {
        AppBase.initialize();
        controller = new VisualQaController();
    }

    function getInitialView() {
        var view = new TaskListView(controller);
        controller.attach(view);
        return [view, new TaskListDelegate(controller, view)];
    }
}

class VisualQaListsController extends VisualQaController {
    function initialize() {
        VisualQaController.initialize();
        mode = "lists";
        selected = 1;
    }
}

class VisualQaListsApp extends App.AppBase {
    var controller;

    function initialize() {
        AppBase.initialize();
        controller = new VisualQaListsController();
    }

    function getInitialView() {
        var view = new TaskListView(controller);
        controller.attach(view);
        return [view, new TaskListDelegate(controller, view)];
    }
}

class VisualQaStressController extends VisualQaController {
    function initialize() {
        VisualQaController.initialize();
        tasks = [
            {
                "id" => "qa-long-1",
                "projectId" => "qa-list-1",
                "title" => "Review the final launch readiness plan with every stakeholder",
                "dueDate" => "2026-08-10T18:30:00+0100",
                "isAllDay" => false
            },
            {
                "id" => "qa-long-2",
                "projectId" => "qa-list-1",
                "title" => "Reply to all outstanding notes from the product review",
                "dueDate" => "2026-08-10T20:00:00+0100",
                "isAllDay" => false
            },
            {
                "id" => "qa-long-3",
                "projectId" => "qa-list-2",
                "title" => "Plan the entire week including training travel and recovery",
                "dueDate" => "2026-08-09",
                "isAllDay" => true,
                "isOverdue" => true
            }
        ];
        selected = 1;
    }
}

class VisualQaStressApp extends App.AppBase {
    var controller;

    function initialize() {
        AppBase.initialize();
        controller = new VisualQaStressController();
    }

    function getInitialView() {
        var view = new TaskListView(controller);
        controller.attach(view);
        return [view, new TaskListDelegate(controller, view)];
    }
}
