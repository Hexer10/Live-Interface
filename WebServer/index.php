<?php

require 'libs/steamauth/steamauth.php';

if (DEVELOPER_MODE > 0) {
    error_reporting(E_ALL);
    ini_set('display_errors', 1);
}

require 'config.php';



function steamidTo2($steamId64)
{
    $accountID = bcsub($steamId64, '76561197960265728');
    return 'STEAM_0:' . bcmod($accountID, '2') . ':' . bcdiv($accountID, 2);
}

?>
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Test1</title>

    <meta name="viewport" content="width=device-width, initial-scale=1, shrink-to-fit=no">
    <meta name="Description" content="Live Source Server interface.">


    <!-- Bootstrap CSS -->
    <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.1.3/css/bootstrap.min.css"
          integrity="sha384-MCw98/SFnGE8fJT3GXwEOngsV7Zt27NXFoaoApmYm81iuXoPkFOJwJ8ERdknLPMO" crossorigin="anonymous">
    <link rel="stylesheet" href="https://cdn.datatables.net/v/bs4/dt-1.10.18/datatables.min.css"/>


</head>
<body>
<div class="container">

    <table id="mainTable" class="table table-striped table-bordered sortable" style="width:100%">
        <thead>
        <tr>
            <th>Name</th>
            <th>Team</th>
            <th>Ping</th>
            <th>Killed by</th>
            <th>Online Time</th>
        </tr>
        </thead>
        <tbody id="tableBody">

        </tbody>
    </table>
    <?php
    if (isset($_SESSION['steamid'])) {
        require 'libs/steamauth/userInfo.php';

        echo '<p>Hello ' . $steamprofile['personaname'] . ' . <a href="?logout">Click to logout!</a></p>';
        echo '<div id="steamid64" hidden>' . $steamprofile['steamid'] . '</div>';
        echo '<div id="steamid" hidden>' . steamidTo2($steamprofile['steamid']) . '</div>';

    } else {
        loginbutton();
    }
    ?>
    <p> Current map: <span id="map"></span></p>

    <form id="commandForm" class="form-inline" hidden>
        <div class="form-group">
            <label for="inputCommand" class="sr-only">Command</label>
            <input required type="text" class="form-control" id="inputCommand" placeholder="Command">
        </div>
        <button type="submit" class="btn btn-primary mb-2">Send command</button>
    </form>
</div>
<script src="https://code.jquery.com/jquery-3.3.1.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/popper.js/1.14.3/umd/popper.min.js"
        integrity="sha384-ZMP7rVo3mIykV+2+9J3UJ46jBk0WLaUAdn689aCwoqbBJiSnjAK/l8WvCWPIPm49"
        crossorigin="anonymous"></script>
<script src="https://stackpath.bootstrapcdn.com/bootstrap/4.1.3/js/bootstrap.min.js"
        integrity="sha384-ChfqqxuZUCnJSK3+MXmPNIyE6ZbWh2IMqE241rYiqJxyMiZ6OW/JmZQ5stwEULTy"
        crossorigin="anonymous"></script>
<script src="https://cdn.datatables.net/v/bs4/dt-1.10.18/datatables.min.js"></script>

<!--suppress JSValidateTypes -->
<script>


    //Stock functions
    function htmlEncode(value) {
        // Create a in-memory div, set its inner text (which jQuery automatically encodes)
        // Then grab the encoded contents back out. The div never exists on the page.
        return $('<div/>').text(value).html();
    }

    $(function () { //Page loaded
        const ws = new WebSocket('<?=WS_URL?>',);
        const table = $('#mainTable').DataTable();
        const steamid = $('#steamid').text();

        // $(table).DataTable();


        ws.onopen = function () {
            console.log('Connection open!');
            if (steamid !== "") {
                const data = {};
                data['steamid'] = steamid;
                data['event'] = 'adminCheck';
                ws.send(JSON.stringify(data));
            }
        };

        ws.onmessage = function (evt) {
            const data = JSON.parse(evt.data);

            //Temporary solution
            try {
                switch (data['event']) {
                    case 'join': {
                        if (!data['bot']) {
                            if (data['steamid64'] === $('#steamid64').text())
                                table.row.add($(`<tr data-steamid64='${data['steamid64']}' id="${data['id']}"><th><a class='text-danger' href='https://steamcommunity.com/profiles/${data['steamid64']}'>${htmlEncode(data['name'])}</a></th><th>${htmlEncode(data['team'])}</th><th></th><th></th><th></th></tr>`)).draw();
                            else
                                table.row.add($(`<tr data-steamid64='${data['steamid64']}' id="${data['id']}"><th><a href='https://steamcommunity.com/profiles/${data['steamid64']}'>${htmlEncode(data['name'])}</a></th><th>${htmlEncode(data['team'])}</th><th></th><th></th><th></th></tr>`)).draw();

                        }
                        else
                            table.row.add($(`<tr id="${data['id']}"><th>${htmlEncode(data['name'])}</th><th>${htmlEncode(data['team'])}</th><th></th><th></th><th></th><th></th>`)).draw();

                        break;
                    }
                    case 'quit': {
                        table.rows(`#${data['id']}`).remove().draw();
                        break;
                    }
                    case 'team': {
                        table.cell($(`#${data['id']}`).children().eq(1)).data(data['team']).draw();
                        break;
                    }
                    case 'ping': {
                        table.cell($(`#${data['id']}`).children().eq(2)).data(data['ping']).draw();
                        table.cell($(`#${data['id']}`).children().eq(4)).data(new Date(data['onlineTime'] * 1000).toISOString().substr(11, 8)).draw();
                        break;
                    }
                    case 'death': {
                        table.cell($(`#${data['id']}`).children().eq(3)).data(data['by']).draw();
                        break;
                    }
                    case 'adminCheck': {
                        if (data['isAdmin']) {
                            $('#commandForm').removeAttr('hidden');
                        }
                        break;
                    }
                    case 'commandSend': {
                        //TODO: Show the result to the client.
                        console.log(data);
                        break;
                    }
                    case 'serverInfo': {
                        $('#map').text(data['map']);
                        break;
                    }
                    default: {
                        console.log(`Method ${data['event']} not implemented!`);
                    }
                }
            } catch (e) {
                if (!(e instanceof TypeError))
                    throw(e);
            }

        };

        ws.onclose = function () {
            console.log('Connection closed');
        };

        $(document).on('submit', '#commandForm', function () {
            event.preventDefault();
            const input = $('#inputCommand');
            const value = input.val();
            if (ws.readyState === WebSocket.OPEN) {
                input.val('');

                $.ajax({
                    url: 'ajax/send.php',
                    method: 'post',
                    data: {
                        'command': value
                    },
                    async: true
                })
            }
        });
    });
</script>
</body>
</html>