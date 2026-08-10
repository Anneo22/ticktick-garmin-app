using Toybox.Application as App;

class LocalStore {
    const RELAY_TOKEN = "relayToken";
    const DEVICE_SECRET = "deviceSecret";
    const USER_CODE = "userCode";
    const VERIFICATION_URL = "verificationUrl";
    const TASKS = "tasks";
    const QUEUE = "mutationQueue";

    function getRelayToken() {
        return App.Storage.getValue(RELAY_TOKEN);
    }

    function setRelayToken(value) {
        App.Storage.setValue(RELAY_TOKEN, value);
    }

    function getDeviceSecret() {
        return App.Storage.getValue(DEVICE_SECRET);
    }

    function setPendingPair(deviceSecret, userCode, verificationUrl) {
        App.Storage.setValue(DEVICE_SECRET, deviceSecret);
        App.Storage.setValue(USER_CODE, userCode);
        App.Storage.setValue(VERIFICATION_URL, verificationUrl);
    }

    function getUserCode() {
        return App.Storage.getValue(USER_CODE);
    }

    function getVerificationUrl() {
        return App.Storage.getValue(VERIFICATION_URL);
    }

    function clearPendingPair() {
        App.Storage.deleteValue(DEVICE_SECRET);
        App.Storage.deleteValue(USER_CODE);
        App.Storage.deleteValue(VERIFICATION_URL);
    }

    function getTasks() {
        var tasks = App.Storage.getValue(TASKS);
        return tasks == null ? [] : tasks;
    }

    function setTasks(tasks) {
        App.Storage.setValue(TASKS, tasks);
    }

    function getQueue() {
        var queue = App.Storage.getValue(QUEUE);
        return queue == null ? [] : queue;
    }

    function setQueue(queue) {
        App.Storage.setValue(QUEUE, queue);
    }

    function unpair() {
        App.Storage.deleteValue(RELAY_TOKEN);
        App.Storage.deleteValue(TASKS);
        App.Storage.deleteValue(QUEUE);
        clearPendingPair();
    }
}
