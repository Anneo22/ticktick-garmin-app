using Toybox.WatchUi as Ui;

class TaskListDelegate extends Ui.BehaviorDelegate {
    var controller;
    var view;

    function initialize(taskController, taskView) {
        BehaviorDelegate.initialize();
        controller = taskController;
        view = taskView;
    }

    function onSelect() {
        controller.activate();
        return true;
    }

    function onNextPage() {
        controller.move(1);
        return true;
    }

    function onPreviousPage() {
        controller.move(-1);
        return true;
    }

    function onMenu() {
        controller.cycleMode();
        return true;
    }

    function onBack() {
        return controller.goBack();
    }

    function onTap(event) {
        return view.handleTap(event.getCoordinates());
    }

    function onSwipe(event) {
        var direction = event.getDirection();
        if (direction == Ui.SWIPE_UP) {
            controller.move(1);
        } else if (direction == Ui.SWIPE_DOWN) {
            controller.move(-1);
        } else if (direction == Ui.SWIPE_LEFT) {
            controller.cycleMode();
        } else if (direction == Ui.SWIPE_RIGHT) {
            controller.goBack();
        }
        return true;
    }
}
