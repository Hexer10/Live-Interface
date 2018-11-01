<?php
header('Content-Type: application/json');
error_reporting(E_ALL - E_NOTICE );
//ini_set('display_errors', 1);

$reply = array();
$reply['success'] = false;
require '../config.php';


if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);

    $reply['error'] = 'Invalid request method';
    die(json_encode($reply));
}

if (empty($_POST['command'])) {
    http_response_code(401);

    $reply['error'] = 'Missing required param \'command\'';
    die(json_encode($reply));
}


require '../libs/steamauth/steamauth.php';

if (!isset($_SESSION['steamid'])) {
    http_response_code(400);

    $reply['error'] = 'Invalid authentication';
    die(json_encode($reply));
}

require '../libs/steamauth/userInfo.php';
require  '../libs/SteamCondenser/steam-condenser.php';


$server = new SourceServer(RCON_IP);
try {
    $server->rconAuth(RCON_PASSWORD);

    $cmd = array();
    $cmd['command'] = $_POST['command'];
    $cmd['ip'] = $_SERVER['REMOTE_ADDR'];
    $cmd['steamid'] = $steamprofile['steamid'];

    exit($server->rconExec('sm_runLiveCmd '. json_encode($cmd)));
} catch(RCONNoAuthException $e) {
    $reply['error'] = 'Invalid Server password';
    die(json_encode($reply));
} catch (TimeoutException $e) {
    $reply['error'] = 'Connection timed out';
    die(json_encode($reply));
} finally {
    $server->disconnect();
}

