//#define DEBUG 1
#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <hexstocks>
#include <json>
#include <websocket>

#define PLUGIN_NAME           "Live Interface"
#define PLUGIN_VERSION        "1.0"

#pragma newdecls required
#pragma semicolon 1


// Master Socket
WebsocketHandle MasterSocket;

// An adt_array of all child socket handles
ArrayList ChildSockets;

//Cvars
ConVar cv_sWebSocketIP;
ConVar cv_iWebSocketPort;


char sCurrentMap[64];

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = "Hexah",
	description = "",
	version = PLUGIN_VERSION,
	url = "github.com/Hexer10"

};
/*** Startup ***/
public void OnPluginStart()
{
	Debug_Print("Hello world!");
	
	cv_sWebSocketIP = CreateConVar("sm_liveinterface_ip", "127.0.0.1", "The websocket server listen IP");
	cv_iWebSocketPort = CreateConVar("sm_liveinterface_port", "6000", "The websocket server listen PORT");
	AutoExecConfig();
	
	//Hooks
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_disconnect", Event_PlayerQuit);
	
	ChildSockets = new ArrayList();
	
	CreateTimer(1.0, Timer_SendInfo, _, TIMER_REPEAT);
	
	RegServerCmd("sm_runLiveCmd", Cmd_LiveCmd, "Used to recive command from the live interface. - Don't issue this command directly");
}

public void OnAllPluginsLoaded()
{
	//Open the websocket.
	char sServerIP[40];
	cv_sWebSocketIP.GetString(sServerIP, sizeof(sServerIP));
	
	if (MasterSocket == INVALID_WEBSOCKET_HANDLE)
		MasterSocket = Websocket_Open(sServerIP, cv_iWebSocketPort.IntValue, OnWebsocketIncoming, OnWebsocketMasterError, OnWebsocketMasterClose);
	
	Debug_Print("Listening on: %s:%i", sServerIP, cv_iWebSocketPort.IntValue);
}

public void OnMapStart()
{
	//Get & Update the current map on round start.
	GetCurrentMap(sCurrentMap, sizeof(sCurrentMap));
	JSON_Object jsonObj = new JSON_Object();
	char sOutput[128];
		
	jsonObj.SetString("event", "serverInfo");
	jsonObj.SetString("map", sCurrentMap);
		
	jsonObj.Encode(sOutput, sizeof(sOutput));
	WebSocket_SendToAll(sOutput);
}

/*** Commands ***/
public Action Cmd_LiveCmd(int args)
{
	char sArgs[512];
	char sOutput[512];
	GetCmdArgString(sArgs, sizeof(sArgs));
	
	StripQuotes(sArgs);
	
	//RecivedJsonObject
	JSON_Object RecivedJsonObj = json_decode(sArgs);
	JSON_Object jsonObj = new JSON_Object();
	
	if (RecivedJsonObj == null)
	{
		jsonObj.SetBool("success", false);
		jsonObj.SetString("error", "Invalid json string");
		jsonObj.Encode(sOutput, sizeof(sOutput));
		WebSocket_SendToAll(sOutput);
		return Plugin_Handled;
	}
	
	char sCmd[256];
	char sSteamID[64];
	
	RecivedJsonObj.GetString("command", sCmd, sizeof(sCmd));
	RecivedJsonObj.GetString("steamid", sSteamID, sizeof(sSteamID));
	jsonObj.SetString("event", "commandSend");
	
	AdminId admin = FindAdminByIdentity("steam", sSteamID);
	if (admin == INVALID_ADMIN_ID)
	{
		jsonObj.SetBool("success", false);
		jsonObj.SetString("error", "Invalid Admin");
		jsonObj.Encode(sOutput, sizeof(sOutput));
		WebSocket_SendToAll(sOutput);
	}
	else if (CheckAccess(admin, "rt_update_rcon", ADMFLAG_RCON) && CheckAccess(admin, sCmd, ADMFLAG_RCON))
	{
		jsonObj.SetBool("success", true);
		jsonObj.SetString("command", sCmd);
		jsonObj.SetKeyHidden("command", true);
		RequestFrame(Frame_SendSuccess, jsonObj);

	}
	else
	{
		jsonObj.SetBool("success", false);
		jsonObj.SetString("error", "Invalid Permissions");
		jsonObj.Encode(sOutput, sizeof(sOutput));
		WebSocket_SendToAll(sOutput);
	}
		
	return Plugin_Handled;
}

public void Frame_SendSuccess(JSON_Object jsonObj)
{
	char sReply[128];
	char sCmd[128];
	char sOutput[512];
	
	jsonObj.GetString("command", sCmd, sizeof(sCmd));
	ServerCommandEx(sReply, sizeof(sReply), sCmd);
	Debug_Print("The reply: %s", sReply);
	Debug_Print("The cmd: %s", sCmd);
	
		
	//TODO: Temp fix
	ReplaceString(sReply, sizeof(sReply), "\"", "''");
	
	jsonObj.SetString("reply", sReply);
			
	jsonObj.Encode(sOutput, sizeof(sOutput));
	WebSocket_SendToAll(sOutput);
}

/*** Events ***/

public void OnClientPutInServer(int client)
{
	//Check if is a real-connection and is not a bot.
	if (!IsFakeClient(client))
		if (RoundToNearest(GetClientTime(client)) >= 5)
			return;
	
	//Send the join client event.
	JSON_Object jsonObj = new JSON_Object();
	char sName[64];
	char sTeam[32];
	bool bBot = IsFakeClient(client);
	
	char sOutput[512];
	
	GetClientName(client, sName, sizeof(sName));
	
	
	jsonObj.SetString("event", "join");
	jsonObj.SetInt("id", GetClientUserId(client));
	jsonObj.SetString("team", sTeam);
	jsonObj.SetString("name", sName);
	jsonObj.SetBool("bot", bBot);
	
	if (!bBot)
	{
		char sSteamID[64];
		GetClientAuthId(client, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
		jsonObj.SetString("steamid64", sSteamID);
	}

	jsonObj.Encode(sOutput, sizeof(sOutput));
	
	WebSocket_SendToAll(sOutput);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	//Send the player spawn event.
	JSON_Object jsonObj = new JSON_Object();
	char sOutput[128];
		
	jsonObj.SetString("event", "death");
	jsonObj.SetInt("id", event.GetInt("userid"));
	jsonObj.SetString("by", "Alive");
		
	jsonObj.Encode(sOutput, sizeof(sOutput));
	
	WebSocket_SendToAll(sOutput);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	//Send the player death event.
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	
	JSON_Object jsonObj = new JSON_Object();
	char sOutput[128];
	char sName[64];
	
	GetClientName(attacker, sName, sizeof(sName));
		
	jsonObj.SetString("event", "death");
	jsonObj.SetInt("id", event.GetInt("userid"));
	jsonObj.SetString("by", sName);
		
	jsonObj.Encode(sOutput, sizeof(sOutput));
	
	WebSocket_SendToAll(sOutput);
}

public void Event_PlayerQuit(Event event, const char[] name, bool dontBroadcast)
{
	//Send the player quit event.
	JSON_Object jsonObj = new JSON_Object();
	char sOutput[512];
	
	jsonObj.SetString("event", "quit");
	jsonObj.SetInt("id", event.GetInt("userid"));

	jsonObj.Encode(sOutput, sizeof(sOutput));
	
	WebSocket_SendToAll(sOutput);
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	//Send the team change event.
	char sTeam[64];
	GetTeamName(event.GetInt("team"), sTeam, sizeof(sTeam));
	
	JSON_Object jsonObj = new JSON_Object();
	char sOutput[512];
	jsonObj.SetInt("id", event.GetInt("userid"));
	

	jsonObj.SetString("event", "team");
	jsonObj.SetString("team", sTeam);

	jsonObj.Encode(sOutput, sizeof(sOutput));
	
	for(int i = 0; i < ChildSockets.Length; i++)
	{
		WebsocketHandle socket = ChildSockets.Get(i);
		Websocket_Send(socket, SendType_Text, sOutput);
	}
}

/*** Sockets Event **/

public Action OnWebsocketIncoming(WebsocketHandle websocket, WebsocketHandle newWebsocket, const char[] remoteIP, int remotePort, char protocols[256])
{
	//Hook & push the new websocket
	Websocket_HookChild(newWebsocket, OnWebsocketReceive, OnWebsocketDisconnect, OnChildWebsocketError);
	ChildSockets.Push(newWebsocket);
	
	Debug_Print("New connection: %s:%i | Ready: %i", remoteIP, remotePort, 0);
	
	//Wait to send data to the socket
	CreateTimer(1.0, Timer_SendData, newWebsocket);

	return Plugin_Continue;
}

public void OnWebsocketReceive(WebsocketHandle websocket, WebsocketSendType iType, const char[] receiveData, const int dataSize)
{
	if (iType != SendType_Text)
		return;
	
	Debug_Print("Recived: %s | Size: %i", receiveData, dataSize);

	JSON_Object jsonObj = json_decode(receiveData);
	char sEvent[64];
	
	jsonObj.GetString("event", sEvent , sizeof(sEvent));
	
	//Handle the recived data.
	if (StrEqual(sEvent, "adminCheck")) 
	{
		char sSteamID[64];
		char sOutput[128];
		
		jsonObj.GetString("steamid", sSteamID, sizeof(sSteamID));
		
		jsonObj = new JSON_Object();
		jsonObj.SetString("event", "adminCheck");
		
		AdminId admin = FindAdminByIdentity("steam", sSteamID);
		if (admin != INVALID_ADMIN_ID)
		{
			jsonObj.SetBool("isAdmin", CheckAccess(admin, "rt_update_rcon", ADMFLAG_RCON));
		}
		else
		{
			jsonObj.SetBool("isAdmin", false);
		}
		
		jsonObj.Encode(sOutput, sizeof(sOutput));
		WebSocket_SendToAll(sOutput);
		Debug_Print("Sent: %s", sOutput);
	}
	else
	{
		LogError("Method: %s not implemented!", sEvent);
	}
}

public void OnWebsocketDisconnect(WebsocketHandle websocket)
{
	ChildSockets.Erase(ChildSockets.FindValue(websocket));
}

public void OnWebsocketMasterClose(WebsocketHandle websocket)
{
	MasterSocket = INVALID_WEBSOCKET_HANDLE;
	ChildSockets.Clear();
}

public void OnWebsocketMasterError(WebsocketHandle websocket, const int errorType, const int errorNum)
{
	LogError("MASTER SOCKET ERROR: handle: %d type: %d, errno: %d", view_as<int>(websocket), errorType, errorNum);
	MasterSocket = INVALID_WEBSOCKET_HANDLE;
	ChildSockets.Clear();
}

public void OnChildWebsocketError(WebsocketHandle websocket, const int errorType, const int errorNum)
{
	LogError("CHILD SOCKET ERROR: handle: %d, type: %d, errno: %d", view_as<int>(websocket), errorType, errorNum);
	ChildSockets.Erase(ChildSockets.FindValue(websocket));
}

/*** Timers ***/
public Action Timer_SendData(Handle timer, WebsocketHandle websocket)
{
	if (websocket == INVALID_WEBSOCKET_HANDLE)
		return;
	
	//Send the list of already connected players.
	for(int i = 1; i <= MaxClients; i++) if (IsClientInGame(i))
	{
		JSON_Object jsonObj = new JSON_Object();
		char sName[64];
		char sTeam[32];
		bool bBot = IsFakeClient(i);
		char sOutput[512];
	
		GetClientName(i, sName, sizeof(sName));
		GetTeamName(GetClientTeam(i), sTeam, sizeof(sTeam));
	
		jsonObj.SetString("event", "join");
		jsonObj.SetInt("id", GetClientUserId(i));
		jsonObj.SetString("team", sTeam);
		jsonObj.SetString("name", sName);
		jsonObj.SetBool("bot", bBot);
		
		if (!bBot)
		{
			char sSteamID[64];
			GetClientAuthId(i, AuthId_SteamID64, sSteamID, sizeof(sSteamID));
			jsonObj.SetString("steamid64", sSteamID);
		}

		jsonObj.Encode(sOutput, sizeof(sOutput));
		Websocket_Send(websocket, SendType_Text, sOutput);
		Debug_Print("Send: %s", sOutput);
	}
	
	if (sCurrentMap[0] == '\0')
		return;
	
	//Send the current map.
	JSON_Object jsonObj = new JSON_Object();
	char sOutput[128];
		
	jsonObj.SetString("event", "serverInfo");
	jsonObj.SetString("map", sCurrentMap);
		
	jsonObj.Encode(sOutput, sizeof(sOutput));
	WebSocket_SendToAll(sOutput);
}

public Action Timer_SendInfo(Handle timer)
{
	for (int i = 1; i <= MaxClients; i++)if (IsClientInGame(i) && !IsFakeClient(i))
	{
		JSON_Object jsonObj = new JSON_Object();
		char sOutput[64];
		
		//Get the ping
		int ping = GetEntProp(GetPlayerResourceEntity(), Prop_Send, "m_iPing", _, i);
		jsonObj.SetString("event", "ping");
		jsonObj.SetInt("id", GetClientUserId(i));
		
		jsonObj.SetInt("ping", ping);
		//Get the online time.
		jsonObj.SetInt("onlineTime", RoundToNearest(GetClientTime(i)));
		
		jsonObj.Encode(sOutput, sizeof(sOutput));
	
		WebSocket_SendToAll(sOutput);
	}
}

/*** Stocks ***/

/*
		char sSteamID[64];
		char sOutput[512];
		char sFullCmd[512];
		char sCmd[64];
		
		jsonObj.GetString("steamid", sSteamID, sizeof(sSteamID));
		jsonObj.GetString("command", sFullCmd, sizeof(sFullCmd));
		
		TrimString(sFullCmd);
		Format(sFullCmd, sizeof(sFullCmd), "sm_%s", sFullCmd);
		
		int index = SplitString(sFullCmd, " ", sCmd, sizeof(sCmd));
		if (index == -1)
			strcopy(sCmd, sizeof(sCmd), sFullCmd);
		
		jsonObj.GetString("steamid", sSteamID, sizeof(sSteamID));
		
		jsonObj = new JSON_Object();
		jsonObj.SetString("event", "sendCommand");
		
		AdminId admin = FindAdminByIdentity("steam", sSteamID);
		if (admin == INVALID_ADMIN_ID)
		{
			jsonObj.SetBool("success", false);
			jsonObj.SetString("error", "Invalid Admin");
			jsonObj.Encode(sOutput, sizeof(sOutput));
			WebSocket_SendToAll(sOutput);
		}
		else if (CheckAccess(admin, "rt_update_rcon", ADMFLAG_RCON) && CheckAccess(admin, sCmd, ADMFLAG_RCON))
		{
			jsonObj.SetBool("success", true);
			char sReply[512];
			ServerCommandEx(sReply, sizeof(sReply), sFullCmd);
			
			//TODO: Temp fix
			ReplaceString(sReply, sizeof(sReply), "\"", "''");
			
			jsonObj.SetString("reply", sReply);
			
			jsonObj.Encode(sOutput, sizeof(sOutput));
			WebSocket_SendToAll(sOutput);
		}
		else
		{
			jsonObj.SetBool("success", false);
			jsonObj.SetString("error", "Invalid Permissions");
			jsonObj.Encode(sOutput, sizeof(sOutput));
			WebSocket_SendToAll(sOutput);
		}
		*/
//Send data to all pushed sockets.
stock void WebSocket_SendToAll(const char[] format, any ...)
{
	char sBuffer[512];
	VFormat(sBuffer, sizeof(sBuffer), format, 2);
	
	for(int i = 0; i < ChildSockets.Length; i++)
	{
		WebsocketHandle socket = ChildSockets.Get(i);
		Websocket_Send(socket, SendType_Text, sBuffer);
	}
}