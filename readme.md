# Live Interface for Source Servers

This is a web interface that shows the servers info _(like current map)_ and the players list, that updates in real time.
You can also login-in with steam, and if you would have permissions in the server you can even send commands.

This is still in a beta stage, so expect issues if you are trying to use it, I don't suggest using it in a production server in its current state.

There are some features that still need to be completed, see the issues tab for a list.
Especially the UX of the website.

## Installation

#### Gameserver
1. Install the socket extension: https://forums.alliedmods.net/showthread.php?t=67640?t=67640
2. Install the websocket plugin: https://forums.alliedmods.net/showthread.php?t=182615
    * To make it work properly I had to make a small edit on the line 760, by commeting it, you can find the compile binary in the plugins folder.
3. Install the live interface find that is located inside the plugins folder.
4. Edit the settings located in `cfg/sourcemod/`
#### WebServer
1. Upload to your webserver the files located inside `WebServer/` then edit `config.php` according to your settings.

Optional:
To support `https / wss ` you'd need to configure a `reverse proxy`, this is an example for nginx
```
server {
	listen 443;
	server_name 'ws.example.com';
  
	location / {
	    proxy_pass http://127.0.0.1:60000;
		proxy_http_version 1.1;
		proxy_set_header Upgrade $http_upgrade;
		proxy_set_header Connection "Upgrade";
	}
}
```

## Screenshots
![Imgur](https://i.imgur.com/0UGJDZx.png)
![Imgur](https://i.imgur.com/HZMbfUY.png)


