using Toybox.Application as App;

class TickTickGarminApp extends App.AppBase {
    var controller;

    function initialize() {
        AppBase.initialize();
        controller = new TaskController();
    }

    function onStart(state) {
    }

    function onStop(state) {
    }

    function getInitialView() {
        var view = new TaskListView(controller);
        controller.attach(view);
        return [view, new TaskListDelegate(controller, view)];
    }
}
