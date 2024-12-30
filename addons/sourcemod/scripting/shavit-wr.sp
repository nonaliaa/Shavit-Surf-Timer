/*
 * shavit's Timer - World Records
 * by: shavit, SaengerItsWar, KiD Fearless, rtldg, BoomShotKapow, Nuko
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
 *
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

#include <sourcemod>
#include <convar_class>
#include <dhooks>

#include <shavit/core>
#include <shavit/wr>
#include <shavit/steamid-stocks>

#undef REQUIRE_PLUGIN
#include <shavit/rankings>
#include <shavit/zones>
#include <adminmenu>

#pragma newdecls required
#pragma semicolon 1

// #define DEBUG

enum struct wrcache_t
{
	int iLastStyle;
	int iLastTrack;
	int iLastStage;
	int iPagePosition;
	bool bForceStyle;
	bool bPendingMenu;
	char sClientMap[PLATFORM_MAX_PATH];
	float fWRs[STYLE_LIMIT];
}

bool gB_Late = false;
bool gB_Rankings = false;
bool gB_Stats = false;
bool gB_AdminMenu = false;

// forwards
Handle gH_OnWorldRecord = null;
Handle gH_OnFinish_Post = null;
Handle gH_OnWRDeleted = null;
Handle gH_OnWorstRecord = null;
Handle gH_OnFinishMessage = null;
Handle gH_OnWorldRecordsCached = null;
Handle gH_OnStageWorldRecordsCached = null;
Handle gH_OnFinishStage_Post = null;

// database handle
int gI_Driver = Driver_unknown;
Database gH_SQL = null;
bool gB_Connected = false;

// cache
wrcache_t gA_WRCache[MAXPLAYERS+1];
StringMap gSM_StyleCommands = null;

char gS_Map[PLATFORM_MAX_PATH];
ArrayList gA_ValidMaps = null;

// current wr stats
float gF_WRTime[STYLE_LIMIT][TRACKS_SIZE];
float gF_WRStartVelocity[STYLE_LIMIT][TRACKS_SIZE];
float gF_WREndVelocity[STYLE_LIMIT][TRACKS_SIZE];
int gI_WRRecordID[STYLE_LIMIT][TRACKS_SIZE];
int gI_WRSteamID[STYLE_LIMIT][TRACKS_SIZE];
StringMap gSM_WRNames = null;
ArrayList gA_Leaderboard[STYLE_LIMIT][TRACKS_SIZE];
bool gB_LoadedCache[MAXPLAYERS+1];
float gF_PlayerRecord[MAXPLAYERS+1][STYLE_LIMIT][TRACKS_SIZE];
float gF_PlayerStartVelocity[MAXPLAYERS+1][STYLE_LIMIT][TRACKS_SIZE];
float gF_PlayerEndVelocity[MAXPLAYERS+1][STYLE_LIMIT][TRACKS_SIZE];
int gI_PlayerCompletion[MAXPLAYERS+1][STYLE_LIMIT][TRACKS_SIZE];

// stage wr stats
float gF_StageWRTime[STYLE_LIMIT][MAX_STAGES];
float gF_StageWRStartVelocity[STYLE_LIMIT][MAX_STAGES];
float gF_StageWREndVelocity[STYLE_LIMIT][MAX_STAGES];
int gI_StageWRRecordID[STYLE_LIMIT][MAX_STAGES];
int gI_StageWRSteamID[STYLE_LIMIT][MAX_STAGES];
StringMap gSM_StageWRNames = null;
ArrayList gA_StageLeaderboard[STYLE_LIMIT][MAX_STAGES];
bool gB_LoadedStageCache[MAXPLAYERS+1];
float gF_PlayerStageRecord[MAXPLAYERS+1][STYLE_LIMIT][MAX_STAGES];
float gF_PlayerStageStartVelocity[MAXPLAYERS+1][STYLE_LIMIT][MAX_STAGES];
float gF_PlayerStageEndVelocity[MAXPLAYERS+1][STYLE_LIMIT][MAX_STAGES];
int gI_PlayerStageCompletion[MAXPLAYERS+1][STYLE_LIMIT][MAX_STAGES];

// admin menu
TopMenu gH_AdminMenu = null;
TopMenuObject gH_TimerCommands = INVALID_TOPMENUOBJECT;

// table prefix
char gS_MySQLPrefix[32];

// cvars
Convar gCV_RecordsLimit = null;
Convar gCV_RecentLimit = null;


// timer settings
int gI_Styles = 0;
stylestrings_t gS_StyleStrings[STYLE_LIMIT];

// chat settings
chatstrings_t gS_ChatStrings;

// stage cp times (wrs/pbs)
float gA_StageCP_WR[STYLE_LIMIT][TRACKS_SIZE][MAX_STAGES]; // WR run's stage times
ArrayList gA_StageCP_PB[MAXPLAYERS+1][STYLE_LIMIT][TRACKS_SIZE]; // player's best WRCP times or something


Menu gH_PBMenu[MAXPLAYERS+1];
int gI_PBMenuPos[MAXPLAYERS+1];
bool gB_RRSelectMain[MAXPLAYERS+1];
bool gB_RRSelectBonus[MAXPLAYERS+1];
bool gB_RRSelectStage[MAXPLAYERS+1];

public Plugin myinfo =
{
	name = "[shavit-surf] World Records",
	author = "shavit, SaengerItsWar, KiD Fearless, rtldg, BoomShotKapow, Nuko",
	description = "World records shavit surf timer. (This plugin is base on shavit's bhop timer)",
	version = SHAVIT_SURF_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// natives
	CreateNative("Shavit_GetClientPB", Native_GetClientPB);
	CreateNative("Shavit_SetClientPB", Native_SetClientPB);
	CreateNative("Shavit_GetClientCompletions", Native_GetClientCompletions);
	CreateNative("Shavit_GetClientStartVelocity", Native_GetClientStartVelocity);
	CreateNative("Shavit_GetClientEndVelocity", Native_GetClientEndVelocity);
	CreateNative("Shavit_SetClientStartVelocity", Native_SetClientStartVelocity);
	CreateNative("Shavit_SetClientEndVelocity", Native_SetClientEndVelocity);
	CreateNative("Shavit_GetClientStagePB", Native_GetClientStagePB);
	CreateNative("Shavit_SetClientStagePB", Native_SetClientStagePB);	
	CreateNative("Shavit_GetClientStageCompletions", Native_GetClientStageCompletions);
	CreateNative("Shavit_GetClientStageStartVelocity", Native_GetClientStageStartVelocity);
	CreateNative("Shavit_GetClientStageEndVelocity", Native_GetClientStageEndVelocity);
	CreateNative("Shavit_SetClientStageStartVelocity", Native_SetClientStageStartVelocity);
	CreateNative("Shavit_SetClientStageEndVelocity", Native_SetClientStageEndVelocity);
	CreateNative("Shavit_GetRankForTime", Native_GetRankForTime);
	CreateNative("Shavit_GetRecordAmount", Native_GetRecordAmount);
	CreateNative("Shavit_GetTimeForRank", Native_GetTimeForRank);
	CreateNative("Shavit_GetWorldRecord", Native_GetWorldRecord);
	CreateNative("Shavit_GetWRStartVelocity", Native_GetWRStartVelocity);
	CreateNative("Shavit_GettWREndVelocity", Native_GetWREndVelocity);
	CreateNative("Shavit_GetWRName", Native_GetWRName);
	CreateNative("Shavit_GetWRRecordID", Native_GetWRRecordID);
	CreateNative("Shavit_ReloadLeaderboards", Native_ReloadLeaderboards);
	CreateNative("Shavit_WR_DeleteMap", Native_WR_DeleteMap);
	CreateNative("Shavit_DeleteWR", Native_DeleteWR);
	CreateNative("Shavit_DeleteStageWR", Native_DeleteStageWR);
	CreateNative("Shavit_GetStageCPWR", Native_GetStageCPWR);
	CreateNative("Shavit_GetStageCPPB", Native_GetStageCPPB);
	CreateNative("Shavit_GetStageWorldRecord", Native_GetStageWorldRecord);
	CreateNative("Shavit_GetStageWRStartVelocity", Native_GetStageWRStartVelocity);
	CreateNative("Shavit_GettStageWREndVelocity", Native_GetStageWREndVelocity);
	CreateNative("Shavit_GetStageWRName", Native_GetStageWRName);
	CreateNative("Shavit_GetStageWRRecordID", Native_GetStageWRRecordID);
	CreateNative("Shavit_GetStageRecordAmount", Native_GetStageRecordAmount);
	CreateNative("Shavit_GetStageTimeForRank", Native_GetStageTimeForRank);
	CreateNative("Shavit_GetStageRankForTime", Native_GetStageRankForTime);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("shavit-wr");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("plugin.basecommands");
	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-wr.phrases");

	#if defined DEBUG
	RegConsoleCmd("sm_junk", Command_Junk);
	RegConsoleCmd("sm_printleaderboards", Command_PrintLeaderboards);
	#endif

	gSM_WRNames = new StringMap();
	gSM_StageWRNames = new StringMap();
	gSM_StyleCommands = new StringMap();

	// forwards
	gH_OnWorldRecord = CreateGlobalForward("Shavit_OnWorldRecord", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnFinish_Post = CreateGlobalForward("Shavit_OnFinish_Post", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnWRDeleted = CreateGlobalForward("Shavit_OnWRDeleted", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_String);
	gH_OnWorstRecord = CreateGlobalForward("Shavit_OnWorstRecord", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnFinishMessage = CreateGlobalForward("Shavit_OnFinishMessage", ET_Event, Param_Cell, Param_CellByRef, Param_Array, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_String, Param_Cell);
	gH_OnWorldRecordsCached = CreateGlobalForward("Shavit_OnWorldRecordsCached", ET_Event);
	gH_OnStageWorldRecordsCached = CreateGlobalForward("Shavit_OnStageWorldRecordsCached", ET_Event);
	gH_OnFinishStage_Post = CreateGlobalForward("Shavit_OnFinishStage_Post", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	// player commands
	RegConsoleCmd("sm_wr", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_wr [map]");
	RegConsoleCmd("sm_worldrecord", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_worldrecord [map]");

	RegConsoleCmd("sm_cpwr", Command_WorldRecord, "View the leaderboard of a map's stage. Usage: sm_wrcp [map] [stage number]");
	RegConsoleCmd("sm_swr", Command_WorldRecord, "View the leaderboard of a map's stage. Usage: sm_wrcp [map] [stage number]");
	RegConsoleCmd("sm_stagewr", Command_WorldRecord, "View the leaderboard of a map's stage. Usage: sm_wrcp [map] [stage number]");
	RegConsoleCmd("sm_stageworldrecord", Command_WorldRecord, "View the leaderboard of a map's stage. Usage: sm_wrcp [map] [stage number]");
	RegConsoleCmd("sm_sworldrecord", Command_WorldRecord, "View the leaderboard of a map's stage. Usage: sm_wrcp [map] [stage number]");

	RegConsoleCmd("sm_wrcp", Command_WorldRecord, "View the leaderboard of a map's stage. Usage: sm_wrcp [map] [stage number]");

	RegConsoleCmd("sm_bwr", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_bwr [map] [bonus number]");
	RegConsoleCmd("sm_bworldrecord", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_bworldrecord [map] [bonus number]");
	RegConsoleCmd("sm_bonusworldrecord", Command_WorldRecord, "View the leaderboard of a map. Usage: sm_bonusworldrecord [map] [bonus number]");

	RegConsoleCmd("sm_recent", Command_RecentRecords, "View the recent #1 times set.");
	RegConsoleCmd("sm_recentrecords", Command_RecentRecords, "View the recent #1 times set.");
	RegConsoleCmd("sm_rr", Command_RecentRecords, "View the recent #1 times set.");

	RegConsoleCmd("sm_times", Command_PersonalBest, "View a player's time on a specific map.");
	RegConsoleCmd("sm_time", Command_PersonalBest, "View a player's time on a specific map.");
	RegConsoleCmd("sm_pb", Command_PersonalBest, "View a player's time on a specific map.");

	// delete records
	RegAdminCmd("sm_delete", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface.");
	RegAdminCmd("sm_deleterecord", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface.");
	RegAdminCmd("sm_deleterecords", Command_Delete, ADMFLAG_RCON, "Opens a record deletion menu interface.");
	RegAdminCmd("sm_deleteall", Command_DeleteAll, ADMFLAG_RCON, "Deletes all the records for this map.");

	// delete stage records
	RegAdminCmd("sm_deletestage", Command_DeleteStageRecord, ADMFLAG_RCON, "Opens a stage record deletion menu interface.");
	RegAdminCmd("sm_deletestagerecord", Command_DeleteStageRecord, ADMFLAG_RCON, "Opens a stage record deletion menu interface.");
	RegAdminCmd("sm_deletestagerecords", Command_DeleteStageRecord, ADMFLAG_RCON, "Opens a stage record deletion menu interface.");
	RegAdminCmd("sm_deleteallstage", Command_DeleteAll_Stage, ADMFLAG_RCON, "Deletes all the records for this stage.");

	// cvars
	gCV_RecordsLimit = new Convar("shavit_wr_recordlimit", "50", "Limit of records shown in the WR menu.\nAdvised to not set above 1,000 because scrolling through so many pages is useless.\n(And can also cause the command to take long time to run)", 0, true, 1.0);
	gCV_RecentLimit = new Convar("shavit_wr_recentlimit", "50", "Limit of records shown in the RR menu.", 0, true, 1.0);

	Convar.AutoExecConfig();

	// modules
	gB_Rankings = LibraryExists("shavit-rankings");
	gB_Stats = LibraryExists("shavit-stats");
	gB_AdminMenu = LibraryExists("adminmenu");

	// cache
	gA_ValidMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));

	if(gB_Late)
	{
		Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount());
		Shavit_OnChatConfigLoaded();
		Shavit_OnDatabaseLoaded();

		if (gB_AdminMenu && (gH_AdminMenu = GetAdminTopMenu()) != null)
		{
			OnAdminMenuReady(gH_AdminMenu);
		}
	}

	CreateTimer(2.5, Timer_Dominating, 0, TIMER_REPEAT);
}

public void OnAdminMenuReady(Handle topmenu)
{
	gH_AdminMenu = TopMenu.FromHandle(topmenu);

	if ((gH_TimerCommands = gH_AdminMenu.FindCategory("Timer Commands")) != INVALID_TOPMENUOBJECT)
	{
		gH_AdminMenu.AddItem("sm_deleteall", AdminMenu_DeleteAll, gH_TimerCommands, "sm_deleteall", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_deleteallstage", AdminMenu_DeleteAllStage, gH_TimerCommands, "sm_deleteallstage", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_delete", AdminMenu_Delete, gH_TimerCommands, "sm_delete", ADMFLAG_RCON);
		gH_AdminMenu.AddItem("sm_deletestage", AdminMenu_DeleteStage, gH_TimerCommands, "sm_deletestage", ADMFLAG_RCON);
	}
}

public void AdminMenu_DeleteStage(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%t", "DeleteSingleStageRecord");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteStageRecord(param, 0);
	}
}

public void AdminMenu_DeleteAllStage(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%t", "DeleteAllStageRecords");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteAll_Stage(param, 0);
	}
}

public void AdminMenu_Delete(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%t", "DeleteSingleRecord");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Command_Delete(param, 0);
	}
}

public void AdminMenu_DeleteAll(Handle topmenu,  TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%t", "DeleteAllRecords");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteAll(param, 0);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = true;
	}
	else if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = true;
	}
	else if (StrEqual(name, "adminmenu"))
	{
		gB_AdminMenu = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-rankings"))
	{
		gB_Rankings = false;
	}
	else if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = false;
	}
	else if (StrEqual(name, "adminmenu"))
	{
		gB_AdminMenu = false;
		gH_AdminMenu = null;
		gH_TimerCommands = INVALID_TOPMENUOBJECT;
	}
}

public Action Timer_Dominating(Handle timer)
{
	bool bHasWR[MAXPLAYERS+1];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			char sSteamID[20];
			IntToString(GetSteamAccountID(i), sSteamID, sizeof(sSteamID));
			bHasWR[i] = gSM_WRNames.GetString(sSteamID, sSteamID, sizeof(sSteamID));
		}
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i))
		{
			continue;
		}

		for (int x = 1; x <= MaxClients; x++)
		{
			SetEntProp(i, Prop_Send, "m_bPlayerDominatingMe", bHasWR[x], 1, x);
		}
	}

	return Plugin_Continue;
}

void ResetWRs()
{
	gSM_WRNames.Clear();

	any empty_cells[TRACKS_SIZE];

	for(int i = 0; i < gI_Styles; i++)
	{
		gF_WRTime[i] = empty_cells;
		gF_WRStartVelocity[i] = empty_cells;
		gF_WREndVelocity[i] = empty_cells;
		gI_WRRecordID[i] = empty_cells;
		gI_WRSteamID[i] = empty_cells;
	}
}

void ResetStageWRs()
{
	gSM_StageWRNames.Clear();

	any empty_cells[MAX_STAGES];

	for(int i = 0; i < gI_Styles; i++)
	{
		gF_StageWRTime[i] = empty_cells;
		gF_StageWRStartVelocity[i] = empty_cells;
		gF_StageWREndVelocity[i] = empty_cells;
		gI_StageWRRecordID[i] = empty_cells;
		gI_StageWRSteamID[i] = empty_cells;
	}
}

void ResetStagePBCPs(int client, int style, int track)
{
	for(int i = 0; i < gA_StageCP_PB[client][style][track].Length; i++)
	{
		gA_StageCP_PB[client][style][track].Set(i, 0.0);
	}
}

void ResetLeaderboards()
{
	for(int i = 0; i < gI_Styles; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gA_Leaderboard[i][j].Clear();				
		}
	}
}

void ResetStageLeaderboards()
{
	for(int i = 0; i < gI_Styles; i++)
	{
		for(int j = 0; j < MAX_STAGES; j++)
		{
			gA_StageLeaderboard[i][j].Clear();				
		}
	}
}

public void OnMapStart()
{
	if(!gB_Connected)
	{
		return;
	}

	GetLowercaseMapName(gS_Map);

	UpdateWRCache();

	gA_ValidMaps.Clear();

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "SELECT map FROM %smapzones GROUP BY map UNION SELECT map FROM %splayertimes GROUP BY map ORDER BY map ASC;", gS_MySQLPrefix, gS_MySQLPrefix);
	QueryLog(gH_SQL, SQL_UpdateMaps_Callback, sQuery, 0, DBPrio_Low);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && IsClientAuthorized(i))
		{
			OnClientAuthorized(i, "");
		}
	}
}

public void OnMapEnd()
{
	ResetWRs();
	ResetStageWRs();
}

public void SQL_UpdateMaps_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR maps cache update) SQL query failed. Reason: %s", error);

		return;
	}

	while(results.FetchRow())
	{
		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(0, sMap, sizeof(sMap));
		LowercaseString(sMap);
		gA_ValidMaps.PushString(sMap);
	}

	if (gA_ValidMaps.FindString(gS_Map) == -1)
	{
		gA_ValidMaps.PushString(gS_Map);
	}
}

void RegisterWRCommands(int style)
{
	char sStyleCommands[32][32];
	int iCommands = ExplodeString(gS_StyleStrings[style].sChangeCommand, ";", sStyleCommands, 32, 32, false);

	char sDescription[128];
	FormatEx(sDescription, 128, "View the leaderboard of a map on style %s.", gS_StyleStrings[style].sStyleName);

	for (int x = 0; x < iCommands; x++)
	{
		TrimString(sStyleCommands[x]);
		StripQuotes(sStyleCommands[x]);

		if (strlen(sStyleCommands[x]) < 1)
		{
			continue;
		}


		char sCommand[40];
		FormatEx(sCommand, sizeof(sCommand), "sm_wr%s", sStyleCommands[x]);
		gSM_StyleCommands.SetValue(sCommand, style);
		RegConsoleCmd(sCommand, Command_WorldRecord_Style, sDescription);

		FormatEx(sCommand, sizeof(sCommand), "sm_bwr%s", sStyleCommands[x]);
		gSM_StyleCommands.SetValue(sCommand, style);
		RegConsoleCmd(sCommand, Command_WorldRecord_Style, sDescription);
	}
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	for(int i = 0; i < STYLE_LIMIT; i++)
	{
		if (i < styles)
		{
			Shavit_GetStyleStringsStruct(i, gS_StyleStrings[i]);
			RegisterWRCommands(i);
		}

		for (int j = 0; j < TRACKS_SIZE; j++)
		{
			if (i < styles)
			{
				if (gA_Leaderboard[i][j] == null)
				{
					gA_Leaderboard[i][j] = new ArrayList();
				}

				gA_Leaderboard[i][j].Clear();
			}
			else
			{
				delete gA_Leaderboard[i][j];
			}
		}

		for (int k = 0; k < MAX_STAGES; k++)
		{
			if (i < styles)
			{
				if (gA_StageLeaderboard[i][k] == null)
				{
					gA_StageLeaderboard[i][k] = new ArrayList();
				}

				gA_StageLeaderboard[i][k].Clear();
			}
			else
			{
				delete gA_StageLeaderboard[i][k];
			}
		}
	}

	gI_Styles = styles;
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void OnClientConnected(int client)
{
	wrcache_t empty_cache;
	gA_WRCache[client] = empty_cache;

	gB_LoadedCache[client] = false;
	gB_LoadedStageCache[client] = false;

	gB_RRSelectMain[client] = true;
	gB_RRSelectBonus[client] = true;
	gB_RRSelectStage[client] = true;

	any empty_cells[TRACKS_SIZE];
	any stage_empty_cells[MAX_STAGES];

	for(int i = 0; i < gI_Styles; i++)
	{
		gF_PlayerRecord[client][i] = empty_cells;
		gF_PlayerStartVelocity[client][i] = empty_cells;
		gF_PlayerEndVelocity[client][i] = empty_cells;
		gI_PlayerCompletion[client][i] = empty_cells;

		gF_PlayerStageRecord[client][i] = stage_empty_cells;
		gF_PlayerStageStartVelocity[client][i] = stage_empty_cells;
		gF_PlayerStageEndVelocity[client][i] = stage_empty_cells;
		gI_PlayerStageCompletion[client][i] = stage_empty_cells;
		
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			if(gA_StageCP_PB[client][i][j] != null)
			{
				delete gA_StageCP_PB[client][i][j];
			}

			gA_StageCP_PB[client][i][j] = new ArrayList();
		}
	}
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (gB_Connected && !IsFakeClient(client))
	{
		UpdateClientCache(client);
	}
}

public void OnClientDisconnect(int client)
{
	delete gH_PBMenu[client];
}


void UpdateClientCache(int client)
{
	int iSteamID = GetSteamAccountID(client);

	if(iSteamID == 0)
	{
		return;
	}

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "SELECT %s, style, track, completions, startvel, endvel FROM %splayertimes WHERE map = '%s' AND auth = %d;",
		gI_Driver == Driver_mysql ? "REPLACE(FORMAT(time, 9), ',', '')" : "printf(\"%.9f\", time)", gS_MySQLPrefix, gS_Map, iSteamID);
	QueryLog(gH_SQL, SQL_UpdateCache_Callback, sQuery, GetClientSerial(client), DBPrio_High);

	FormatEx(sQuery, sizeof(sQuery), "SELECT %s, style, stage, completions, startvel, endvel FROM %sstagetimes WHERE map = '%s' AND auth = %d", 
	gI_Driver == Driver_mysql ? "REPLACE(FORMAT(time, 9), ',', '')" : "printf(\"%.9f\", time)", gS_MySQLPrefix, gS_Map, iSteamID);
	QueryLog(gH_SQL, SQL_UpdateStagePBCache_Callback, sQuery, GetClientSerial(client), DBPrio_High);

	FormatEx(sQuery, sizeof(sQuery), "SELECT %s, style, track, checkpoint FROM %scptimes WHERE map = '%s' AND auth = %d", 
		gI_Driver == Driver_mysql ? "REPLACE(FORMAT(time, 9), ',', '')" : "printf(\"%.9f\", time)", gS_MySQLPrefix, gS_Map, iSteamID);
	QueryLog(gH_SQL, SQL_UpdateCPTimesCache_Callback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void SQL_UpdateCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (PB cache update) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	OnClientConnected(client);
	while(results.FetchRow())
	{
		float time = results.FetchFloat(0);
		int style = results.FetchInt(1);
		int track = results.FetchInt(2);

		if(style >= gI_Styles || style < 0 || track >= TRACKS_SIZE)
		{
			continue;
		}

		gF_PlayerRecord[client][style][track] = time;
		gI_PlayerCompletion[client][style][track] = results.FetchInt(3);

		gF_PlayerStartVelocity[client][style][track] = results.FetchFloat(4);
		gF_PlayerEndVelocity[client][style][track] = results.FetchFloat(5);

	}

	gB_LoadedCache[client] = true;
}

public void SQL_UpdateStagePBCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (StagePB cache update) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	while(results.FetchRow())
	{
		float time = results.FetchFloat(0);
		int style = results.FetchInt(1);
		int stage = results.FetchInt(2);

		if(style >= gI_Styles || style < 0 || stage >= MAX_STAGES)
		{
			continue;
		}

		gF_PlayerStageRecord[client][style][stage] = time;
		gI_PlayerStageCompletion[client][style][stage] = results.FetchInt(3);

		gF_PlayerStageStartVelocity[client][style][stage] = results.FetchFloat(4);
		gF_PlayerStageEndVelocity[client][style][stage] = results.FetchFloat(5);
	}

	gB_LoadedStageCache[client] = true;
}

public void SQL_UpdateCPTimesCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (Checkpoint times cache update) SQL query failed. Reason: %s", error);
	}

	int client = GetClientFromSerial(data);
	
	if(client == 0)
	{
		return;
	}

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		for(int j = 0; j < gI_Styles; j++)
		{		
			gA_StageCP_PB[client][j][i].Resize(MAX_STAGES);
			ResetStagePBCPs(client, j, i);
		}
	}

	while(results.FetchRow())
	{
		int style = results.FetchInt(1);
		int track = results.FetchInt(2);
		int stage = results.FetchInt(3);

		if(style >= gI_Styles || style < 0 || track >= TRACKS_SIZE)
		{
			continue;
		}

		// if(gA_StageCP_PB[client][style][track].Length - 1 < stage)
		// {
		// 	gA_StageCP_PB[client][style][track].Resize(Shavit_GetStageCount(track) + 1);
		// }
		
		gA_StageCP_PB[client][style][track].Set(stage, results.FetchFloat(0));
	}
}

void UpdateWRCache(int client = -1)
{
	if (client == -1)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && !IsFakeClient(i))
			{
				UpdateClientCache(i);
			}
		}
	}
	else
	{
		UpdateClientCache(client);
	}

	UpdateLeaderboards();
	UpdateStageLeaderboards();
	UpdateStageCPWR();

	if (client != -1)
	{
		return;
	}
}

void UpdateStageCPWR()
{
	char sQuery[512];

	FormatEx(sQuery, sizeof(sQuery),
		"SELECT style, track, auth, checkpoint, time FROM `%scpwrs` WHERE map = '%s';",
		gS_MySQLPrefix, gS_Map);

	QueryLog(gH_SQL, SQL_UpdateStageCPWR_Callback, sQuery);
}

public void SQL_UpdateStageCPWR_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(!db || !results || error[0])
	{
		LogError("Timer (WR UpdateStageCPWR) SQL query failed. Reason: %s", error);

		return;
	}

	float empty_times[MAX_STAGES];

	for(int i = 0; i < gI_Styles; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gA_StageCP_WR[i][j] = empty_times;
		}
	}

	while(results.FetchRow())
	{
		int style = results.FetchInt(0);
		int track = results.FetchInt(1);
		int stage = results.FetchInt(3);

		gA_StageCP_WR[style][track][stage] = results.FetchFloat(4);
	}
}

public int Native_GetWorldRecord(Handle handler, int numParams)
{
	return view_as<int>(gF_WRTime[GetNativeCell(1)][GetNativeCell(2)]);
}

public int Native_GetWRStartVelocity(Handle handler, int numParams)
{
	return view_as<int>(gF_WRStartVelocity[GetNativeCell(1)][GetNativeCell(2)]);
}

public int Native_GetWREndVelocity(Handle handler, int numParams)
{
	return view_as<int>(gF_WREndVelocity[GetNativeCell(1)][GetNativeCell(2)]);
}

public int Native_ReloadLeaderboards(Handle handler, int numParams)
{
	UpdateWRCache();
	return 1;
}

public int Native_GetWRRecordID(Handle handler, int numParams)
{
	SetNativeCellRef(2, gI_WRRecordID[GetNativeCell(1)][GetNativeCell(3)]);
	return -1;
}

public int Native_GetWRName(Handle handler, int numParams)
{
	int iSteamID = gI_WRSteamID[GetNativeCell(1)][GetNativeCell(4)];
	char sName[MAX_NAME_LENGTH];

	if (iSteamID != 0)
	{
		char sSteamID[20];
		IntToString(iSteamID, sSteamID, sizeof(sSteamID));

		if (gSM_WRNames.GetString(sSteamID, sName, sizeof(sName)))
		{
			SetNativeString(2, sName, GetNativeCell(3));
			return 1;
		}
		else
		{
			FormatEx(sName, sizeof(sName), "[U:1:%u]", iSteamID);
			SetNativeString(2, sName, GetNativeCell(3));
			return 0;
		}
	}

	SetNativeString(2, "none", GetNativeCell(3));
	return 0;
}

public int Native_GetClientPB(Handle handler, int numParams)
{
	return view_as<int>(gF_PlayerRecord[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)]);
}

public int Native_SetClientPB(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int style = GetNativeCell(2);
	int track = GetNativeCell(3);
	float time = GetNativeCell(4);

	gF_PlayerRecord[client][style][track] = time;
	return 1;
}

public int Native_GetClientStartVelocity(Handle handler, int numParams)
{
	return view_as<int>(gF_PlayerStartVelocity[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)]);
}

public int Native_SetClientStartVelocity(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int style = GetNativeCell(2);
	int track = GetNativeCell(3);
	float vel = GetNativeCell(4);

	gF_PlayerStartVelocity[client][style][track] = vel;
	return 1;
}

public int Native_GetClientEndVelocity(Handle handler, int numParams)
{
	return view_as<int>(gF_PlayerEndVelocity[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)]);
}

public int Native_SetClientEndVelocity(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int style = GetNativeCell(2);
	int track = GetNativeCell(3);
	float vel = GetNativeCell(4);

	gF_PlayerEndVelocity[client][style][track] = vel;
	return 1;
}

public int Native_GetClientCompletions(Handle handler, int numParams)
{
	return gI_PlayerCompletion[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)];
}

public int Native_GetRankForTime(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(3);

	if(gA_Leaderboard[style][track] == null || gA_Leaderboard[style][track].Length == 0)
	{
		return 1;
	}

	return GetRankForTime(style, GetNativeCell(2), track);
}

public int Native_GetRecordAmount(Handle handler, int numParams)
{
	return GetRecordAmount(GetNativeCell(1), GetNativeCell(2));
}

public int Native_GetTimeForRank(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int rank = GetNativeCell(2);
	int track = GetNativeCell(3);

	#if defined DEBUG
	Shavit_PrintToChatAll("style %d | rank %d | track %d | amount %d", style, rank, track, GetRecordAmount(style, track));
	#endif

	if(rank > GetRecordAmount(style, track))
	{
		return view_as<int>(0.0);
	}

	return view_as<int>(gA_Leaderboard[style][track].Get(rank - 1));
}

public int Native_GetClientStageCompletions(Handle handler, int numParams)
{
	return gI_PlayerStageCompletion[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)];
}

public int Native_GetStageRankForTime(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int stage = GetNativeCell(3);

	if (gA_StageLeaderboard[style][stage] == null || gA_StageLeaderboard[style][stage].Length == 0)
	{
		return 1;
	}

	return GetStageRankForTime(style, GetNativeCell(2), stage);
}

public int Native_GetStageRecordAmount(Handle handler, int numParams)
{
	return GetStageRecordAmount(GetNativeCell(1), GetNativeCell(2));
}

public int Native_GetStageTimeForRank(Handle handler, int numParams)
{
	int style = GetNativeCell(1);
	int rank = GetNativeCell(2);
	int stage = GetNativeCell(3);

	if(rank > GetStageRecordAmount(style, stage))
	{
		return view_as<int>(0.0);
	}

	return view_as<int>(gA_StageLeaderboard[style][stage].Get(rank - 1));
}

public int Native_WR_DeleteMap(Handle handler, int numParams)
{
	char sMap[PLATFORM_MAX_PATH];
	GetNativeString(1, sMap, sizeof(sMap));
	LowercaseString(sMap);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM %splayertimes WHERE map = '%s';", gS_MySQLPrefix, sMap);
	QueryLog(gH_SQL, SQL_DeleteMap_Callback, sQuery, StrEqual(gS_Map, sMap, false), DBPrio_High);
	return 1;
}

void DeleteWRFinal(int style, int track, const char[] map, int steamid, int recordid, bool update_cache)
{
	if(track == 0)
	{
		DataPack hPack = new DataPack();
		hPack.WriteCell(style);
		hPack.WriteCell(track);
		hPack.WriteString(map);

		char sQuery[256];
		FormatEx(sQuery, sizeof(sQuery),
			"DELETE FROM %scpwrs WHERE map = '%s' AND style = %d AND track = %d;", gS_MySQLPrefix, map, style, track);
		QueryLog(gH_SQL, DeleteWRCPTimes_First_Callback, sQuery, hPack, DBPrio_High);		
	}

	Call_StartForward(gH_OnWRDeleted);
	Call_PushCell(style);
	Call_PushCell(recordid);
	Call_PushCell(track);
	Call_PushCell(0);
	Call_PushCell(steamid);
	Call_PushString(map);
	Call_Finish();

	if (update_cache)
	{
		// pop that sucker from the list so Shavit_OnWRDeleted (mainly in shavit-rankings) can grab the new wr (barring race conditions or whatever...)
		if (gA_Leaderboard[style][track] && gA_Leaderboard[style][track].Length)
		{
			gA_Leaderboard[style][track].Erase(0);
			gF_WRTime[style][track] = Shavit_GetTimeForRank(style, 1, track);
		}

		UpdateWRCache();
	}
}

void DeleteWRCPTimes_First_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	if(results == null)
	{
		LogError("Timer (WR DeleteCPTimes First) SQL query failed. Reason: %s", error);
		delete hPack;
		return;
	}

	hPack.Reset();
	int style = hPack.ReadCell();
	int track = hPack.ReadCell();
	char map[PLATFORM_MAX_PATH];
	hPack.ReadString(map, sizeof(map));

	char sQuery[256];
	FormatEx(sQuery, sizeof(sQuery), "SELECT auth FROM %splayertimes WHERE map = '%s' AND style = %d AND track = %d ORDER BY time ASC LIMIT 1", gS_MySQLPrefix, map, style, track);

	QueryLog(gH_SQL, DeleteWRCPTimes_Second_Callback, sQuery, hPack, DBPrio_High);
}

void DeleteWRCPTimes_Second_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	if(results == null)
	{
		LogError("Timer (WR DeleteCPTimes Second) SQL query failed. Reason: %s", error);
		delete hPack;
		return;
	}

	hPack.Reset();
	int style = hPack.ReadCell();
	int track = hPack.ReadCell();
	char map[PLATFORM_MAX_PATH];
	hPack.ReadString(map, sizeof(map));
	
	delete hPack;

	if(results.FetchRow())
	{
		int steamID = results.FetchInt(0);

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), 
			"INSERT INTO %scpwrs (style, track, map, checkpoint, auth, time) "...
			"SELECT style, track, map, checkpoint, auth, time FROM %scptimes "...
			"WHERE map = '%s' AND style = %d AND track = %d AND auth = %d; ",
			gS_MySQLPrefix, gS_MySQLPrefix, map, style, track, steamID);

		QueryLog(gH_SQL, ReplaceWRCPTimes_Callback, sQuery, 0, DBPrio_High);

		UpdateStageCPWR();
	}
}

public void ReplaceWRCPTimes_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR ReplaceWRCPTimes) SQL query failed. Reason: %s", error);
	}

	return;
}

public void DeleteWR_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	hPack.Reset();

	int style = hPack.ReadCell();
	int track = hPack.ReadCell();
	char map[PLATFORM_MAX_PATH];
	hPack.ReadString(map, sizeof(map));
	bool update_cache = view_as<bool>(hPack.ReadCell());
	int steamid = hPack.ReadCell();
	int recordid = hPack.ReadCell();

	delete hPack;

	if(results == null)
	{
		LogError("Timer (WR DeleteWR) SQL query failed. Reason: %s", error);
		return;
	}

	DeleteWRFinal(style, track, map, steamid, recordid, update_cache);
}

void DeleteWRInner(int recordid, int steamid, DataPack hPack)
{
	hPack.WriteCell(steamid);
	hPack.WriteCell(recordid);

	char sQuery[169];
	FormatEx(sQuery, sizeof(sQuery),
		"DELETE FROM %splayertimes WHERE id = %d;",
		gS_MySQLPrefix, recordid);
	QueryLog(gH_SQL, DeleteWR_Callback, sQuery, hPack, DBPrio_High);
}

public void DeleteWRGetID_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	if(results == null || !results.FetchRow())
	{
		delete hPack;
		LogError("Timer (WR DeleteWRGetID) SQL query failed. Reason: %s", error);
		return;
	}

	DeleteWRInner(results.FetchInt(0), results.FetchInt(1), hPack);
}

void DeleteWR(int style, int track, const char[] map, int steamid, int recordid, bool delete_sql, bool update_cache)
{
	if (delete_sql)
	{
		DataPack hPack = new DataPack();
		hPack.WriteCell(style);
		hPack.WriteCell(track);
		hPack.WriteString(map);
		hPack.WriteCell(update_cache);

		char sQuery[512];

		if (recordid == -1) // missing WR recordid thing...
		{
			FormatEx(sQuery, sizeof(sQuery),			// idk what are this suppose to do, maybe some one use it without record id?
				"SELECT id, auth FROM %swrs WHERE map = '%s' AND style = %d AND track = %d;",
				gS_MySQLPrefix, map, style, track);
			QueryLog(gH_SQL, DeleteWRGetID_Callback, sQuery, hPack, DBPrio_High);
		}
		else
		{
			DeleteWRInner(recordid, steamid, hPack);
		}
	}
	else
	{
		DeleteWRFinal(style, track, map, steamid, recordid, update_cache);
	}
}

void DeleteStageWRFinal(int style, int track, int stage, const char[] map, int steamid, int recordid, bool update_cache)
{
	Call_StartForward(gH_OnWRDeleted);
	Call_PushCell(style);
	Call_PushCell(recordid);
	Call_PushCell(track);
	Call_PushCell(stage);
	Call_PushCell(steamid);
	Call_PushString(map);
	Call_Finish();

	if (update_cache)
	{
		if (gA_Leaderboard[style][track] && gA_Leaderboard[style][track].Length)
		{
			gA_StageLeaderboard[style][stage].Erase(0);
			gF_StageWRTime[style][stage] = Shavit_GetStageTimeForRank(style, 1, stage);
		}

		UpdateWRCache();
	}
}

public void DeleteStageWR_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	hPack.Reset();

	int style = hPack.ReadCell();
	int track = hPack.ReadCell();
	int stage = hPack.ReadCell();
	char map[PLATFORM_MAX_PATH];
	hPack.ReadString(map, sizeof(map));
	bool update_cache = view_as<bool>(hPack.ReadCell());
	int steamid = hPack.ReadCell();
	int recordid = hPack.ReadCell();

	delete hPack;

	if(results == null)
	{
		LogError("Timer (WR DeleteStageWR) SQL query failed. Reason: %s", error);
		return;
	}

	DeleteStageWRFinal(style, track, stage, map, steamid, recordid, update_cache);
}

void DeleteStageWRInner(int recordid, int steamid, DataPack hPack)
{
	hPack.WriteCell(steamid);
	hPack.WriteCell(recordid);

	char sQuery[169];
	FormatEx(sQuery, sizeof(sQuery),
		"DELETE FROM %sstagetimes WHERE id = %d;",
		gS_MySQLPrefix, recordid);
	QueryLog(gH_SQL, DeleteStageWR_Callback, sQuery, hPack, DBPrio_High);
}

public void DeleteStageWRGetID_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	if(results == null || !results.FetchRow())
	{
		delete hPack;
		LogError("Timer (WR DeleteStageWRGetID) SQL query failed. Reason: %s", error);
		return;
	}

	DeleteStageWRInner(results.FetchInt(0), results.FetchInt(1), hPack);
}

void DeleteStageWR(int style, int track, int stage, const char[] map, int steamid, int recordid, bool delete_sql, bool update_cache)
{
	if (delete_sql)
	{
		DataPack hPack = new DataPack();
		hPack.WriteCell(style);
		hPack.WriteCell(track);
		hPack.WriteCell(stage);
		hPack.WriteString(map);
		hPack.WriteCell(update_cache);

		char sQuery[512];

		if (recordid == -1) // missing WR recordid thing...
		{
			FormatEx(sQuery, sizeof(sQuery),			// idk what are this suppose to do, maybe some one use it without record id?
				"SELECT id, auth FROM %sstagewrs WHERE map = '%s' AND style = %d AND track = %d AND stage = %d;",
				gS_MySQLPrefix, map, style, track, gS_MySQLPrefix, map, style, track, stage);
			QueryLog(gH_SQL, DeleteStageWRGetID_Callback, sQuery, hPack, DBPrio_High);
		}
		else
		{
			DeleteStageWRInner(recordid, steamid, hPack);
		}
	}
	else
	{
		DeleteStageWRFinal(style, track, stage, map, steamid, recordid, update_cache);
	}
}

public int Native_DeleteStageWR(Handle handle, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	int stage = GetNativeCell(3);
	char map[PLATFORM_MAX_PATH];
	GetNativeString(4, map, sizeof(map));
	LowercaseString(map);
	int steamid = GetNativeCell(5);
	int recordid = GetNativeCell(6);
	bool delete_sql = view_as<bool>(GetNativeCell(7));
	bool update_cache = view_as<bool>(GetNativeCell(8));

	DeleteStageWR(style, track, stage, map, steamid, recordid, delete_sql, update_cache);
	return 1;
}

public int Native_DeleteWR(Handle handle, int numParams)
{
	int style = GetNativeCell(1);
	int track = GetNativeCell(2);
	char map[PLATFORM_MAX_PATH];
	GetNativeString(3, map, sizeof(map));
	LowercaseString(map);
	int steamid = GetNativeCell(4);
	int recordid = GetNativeCell(5);
	bool delete_sql = view_as<bool>(GetNativeCell(6));
	bool update_cache = view_as<bool>(GetNativeCell(7));

	DeleteWR(style, track, map, steamid, recordid, delete_sql, update_cache);
	return 1;
}

public int Native_GetStageCPWR(Handle plugin, int numParams)
{
	int track = GetNativeCell(1);
	int style = GetNativeCell(2);
	int stage = GetNativeCell(3);
	return view_as<int>(gA_StageCP_WR[style][track][stage]);
}

public int Native_GetStageCPPB(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);
	int style = GetNativeCell(3);
	int stage = GetNativeCell(4);
	float pb = 0.0;
	
	if(stage > gA_StageCP_PB[client][style][track].Length - 1)
	{
		return view_as<int>(pb);
	}
	
	if (gA_StageCP_PB[client][style][track] != null)
	{
		pb = gA_StageCP_PB[client][style][track].Get(stage);
	}

	return view_as<int>(pb);
}

public int Native_GetStageWorldRecord(Handle plugin, int numParams)
{
	return view_as<int>(gF_StageWRTime[GetNativeCell(1)][GetNativeCell(2)]);
}

public int Native_GetStageWRStartVelocity(Handle handler, int numParams)
{
	return view_as<int>(gF_StageWRStartVelocity[GetNativeCell(1)][GetNativeCell(2)]);
}

public int Native_GetStageWREndVelocity(Handle handler, int numParams)
{
	return view_as<int>(gF_StageWREndVelocity[GetNativeCell(1)][GetNativeCell(2)]);
}

public int Native_GetStageWRRecordID(Handle plugin, int numParams)
{
	SetNativeCellRef(2, gI_StageWRRecordID[GetNativeCell(1)][GetNativeCell(3)]);
	return -1;
}

public int Native_GetStageWRName(Handle plugin, int numParams)
{
	int iSteamID = gI_StageWRSteamID[GetNativeCell(1)][GetNativeCell(4)];
	char sName[MAX_NAME_LENGTH];

	if (iSteamID != 0)
	{
		char sSteamID[20];
		IntToString(iSteamID, sSteamID, sizeof(sSteamID));

		if (gSM_StageWRNames.GetString(sSteamID, sName, sizeof(sName)))
		{
			SetNativeString(2, sName, GetNativeCell(3));
			return 1;
		}
		else
		{
			FormatEx(sName, sizeof(sName), "[U:1:%u]", iSteamID);
			SetNativeString(2, sName, GetNativeCell(3));
			return 0;
		}
	}

	SetNativeString(2, "none", GetNativeCell(3));
	return 0;
}

public int Native_GetClientStagePB(Handle plugin, int numParams)
{
	return view_as<int>(gF_PlayerStageRecord[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)]);
}

public int Native_SetClientStagePB(Handle plugin, int numParams)
{
	gF_PlayerStageRecord[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)] = GetNativeCell(4);
	return 0;
}

public int Native_GetClientStageStartVelocity(Handle handler, int numParams)
{
	return view_as<int>(gF_PlayerStageStartVelocity[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)]);
}

public int Native_SetClientStageStartVelocity(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int style = GetNativeCell(2);
	int stage = GetNativeCell(3);
	float vel = GetNativeCell(4);

	gF_PlayerStageStartVelocity[client][style][stage] = vel;
	return 1;
}

public int Native_GetClientStageEndVelocity(Handle handler, int numParams)
{
	return view_as<int>(gF_PlayerStageEndVelocity[GetNativeCell(1)][GetNativeCell(2)][GetNativeCell(3)]);
}

public int Native_SetClientStageEndVelocity(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int style = GetNativeCell(2);
	int stage = GetNativeCell(3);
	float vel = GetNativeCell(4);

	gF_PlayerStageEndVelocity[client][style][stage] = vel;
	return 1;
}

public void SQL_DeleteMap_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR deletemap) SQL query failed. Reason: %s", error);

		return;
	}

	if(view_as<bool>(data))
	{
		OnMapStart();
	}
}

#if defined DEBUG
// debug
public Action Command_Junk(int client, int args)
{
	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery),
		"INSERT INTO %splayertimes (auth, map, time, jumps, date, style, strafes, sync) VALUES (%d, '%s', %f, %d, %d, 0, %d, %.02f);",
		gS_MySQLPrefix, GetSteamAccountID(client), gS_Map, GetRandomFloat(10.0, 20.0), GetRandomInt(5, 15), GetTime(), GetRandomInt(5, 15), GetRandomFloat(50.0, 99.99));

	SQL_LockDatabase(gH_SQL);
	SQL_FastQuery(gH_SQL, sQuery);
	SQL_UnlockDatabase(gH_SQL);

	return Plugin_Handled;
}

public Action Command_PrintLeaderboards(int client, int args)
{
	char sArg[8];
	GetCmdArg(1, sArg, 8);

	int iStyle = StringToInt(sArg);
	int iRecords = GetRecordAmount(iStyle, Track_Main);

	ReplyToCommand(client, "Track: Main - Style: %d", iStyle);
	ReplyToCommand(client, "Current PB: %f", gF_PlayerRecord[client][iStyle][0]);
	ReplyToCommand(client, "Count: %d", iRecords);
	ReplyToCommand(client, "Rank: %d", Shavit_GetRankForTime(iStyle, gF_PlayerRecord[client][iStyle][0], iStyle));

	for(int i = 0; i < iRecords; i++)
	{
		ReplyToCommand(client, "#%d: %f", i, gA_Leaderboard[iStyle][0].Get(i));
	}

	return Plugin_Handled;
}
#endif

int GetTrackRecordCount(int track)
{
	int count = 0;

	for(int i = 0; i < gI_Styles; i++)
	{
		count += GetRecordAmount(i, track);
	}

	return count;
}

int GetStageRecorCount(int stage)
{
	int count = 0;

	for(int i = 0; i < gI_Styles; i++)
	{
		count += GetStageRecordAmount(i, stage);
	}

	return count;
}

public Action Command_DeleteStageRecord(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_DeleteStage_First);
	menu.SetTitle("%T\n ", "DeleteStageSingle", client);

	for(int i = 1; i < MAX_STAGES; i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		int records = GetStageRecorCount(i);

		char sStage[64];
		FormatEx(sStage, sizeof(sStage), "%T %d", "WRStage", client, i);

		if(records > 0)
		{
			FormatEx(sStage, sizeof(sStage), "%s (%T: %d)", sStage, "WRRecord", client, records);
		}

		menu.AddItem(sInfo, sStage, (records > 0) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, 300);

	return Plugin_Handled;
}

public int MenuHandler_DeleteStage_First(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);
		gA_WRCache[param1].iLastTrack = Track_Main;
		gA_WRCache[param1].iLastStage = StringToInt(info);

		DeleteStageSubMenu(param1);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		gH_AdminMenu.DisplayCategory(gH_TimerCommands, param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void DeleteStageSubMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Delete);
	menu.SetTitle("%T\n ", "DeleteMenuTitle", client);

	int[] styles = new int[gI_Styles];
	Shavit_GetOrderedStyles(styles, gI_Styles);

	for(int i = 0; i < gI_Styles; i++)
	{
		int iStyle = styles[i];

		if(Shavit_GetStyleSettingInt(iStyle, "enabled") == -1)
		{
			continue;
		}

		char sInfo[8];
		IntToString(iStyle, sInfo, 8);

		int records = GetStageRecordAmount(i, gA_WRCache[client].iLastStage); 

		char sDisplay[64];
		FormatEx(sDisplay, 64, "%s (%T: %d)", gS_StyleStrings[iStyle].sStyleName, "WRRecord", client, records);

		menu.AddItem(sInfo, (records > 0) ? sDisplay:gS_StyleStrings[iStyle].sStyleName, (records > 0) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);
}


public Action Command_Delete(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_Delete_First);
	menu.SetTitle("%T\n ", "DeleteTrackSingle", client);

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		int records = GetTrackRecordCount(i);

		char sTrack[64];
		GetTrackName(client, i, sTrack, 64);

		if(records > 0)
		{
			Format(sTrack, 64, "%s (%T: %d)", sTrack, "WRRecord", client, records);
		}

		menu.AddItem(sInfo, sTrack, (records > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, 300);

	return Plugin_Handled;
}

public int MenuHandler_Delete_First(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);
		gA_WRCache[param1].iLastTrack = StringToInt(info);
		gA_WRCache[param1].iLastStage = 0;

		DeleteSubmenu(param1);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		gH_AdminMenu.DisplayCategory(gH_TimerCommands, param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void DeleteSubmenu(int client)
{
	Menu menu = new Menu(MenuHandler_Delete);
	menu.SetTitle("%T\n ", "DeleteMenuTitle", client);

	int[] styles = new int[gI_Styles];
	Shavit_GetOrderedStyles(styles, gI_Styles);

	for(int i = 0; i < gI_Styles; i++)
	{
		int iStyle = styles[i];

		if(Shavit_GetStyleSettingInt(iStyle, "enabled") == -1)
		{
			continue;
		}

		char sInfo[8];
		IntToString(iStyle, sInfo, 8);

		char sDisplay[64];
		FormatEx(sDisplay, 64, "%s (%T: %d)", gS_StyleStrings[iStyle].sStyleName, "WRRecord", client, GetRecordAmount(iStyle, gA_WRCache[client].iLastTrack));

		menu.AddItem(sInfo, sDisplay, (GetRecordAmount(iStyle, gA_WRCache[client].iLastTrack) > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);
}

public Action Command_DeleteAll_Stage(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_DeleteAll_Stage_First);
	menu.SetTitle("%T\n ", "DeleteStageAll", client);

	for(int i = 1; i < MAX_STAGES; i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		int records = GetStageRecorCount(i);

		char sStage[64];
		FormatEx(sStage, sizeof(sStage), "%T %d", "WRStage", client, i);

		if(records > 0)
		{
			FormatEx(sStage, sizeof(sStage), "%s (%T: %d)", sStage, "WRRecord", client, records);
		}

		menu.AddItem(sInfo, sStage, (records > 0) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, 300);

	return Plugin_Handled;
}

public int MenuHandler_DeleteAll_Stage_First(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);
		gA_WRCache[param1].iLastTrack = Track_Main;
		gA_WRCache[param1].iLastStage = StringToInt(info);

		Menu subMenu = new Menu(MenuHandler_DeleteAll_Stage_Second);
		subMenu.SetTitle("%T\n ", "DeleteMenuTitle", param1);

		int[] styles = new int[gI_Styles];
		Shavit_GetOrderedStyles(styles, gI_Styles);

		for(int i = 0; i < gI_Styles; i++)
		{
			int iStyle = styles[i];

			if(Shavit_GetStyleSettingInt(iStyle, "enabled") == -1)
			{
				continue;
			}

			char sInfo[8];
			IntToString(iStyle, sInfo, 8);

			int records = GetStageRecordAmount(i, gA_WRCache[param1].iLastStage); 

			char sDisplay[64];
			FormatEx(sDisplay, 64, "%s (%T: %d)", gS_StyleStrings[iStyle].sStyleName, "WRRecord", param1, records);

			subMenu.AddItem(sInfo, (records > 0) ? sDisplay:gS_StyleStrings[iStyle].sStyleName, (records > 0) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
		}

		subMenu.ExitButton = true;
		subMenu.Display(param1, 300);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		gH_AdminMenu.DisplayCategory(gH_TimerCommands, param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_DeleteAll_Stage_Second(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);
		gA_WRCache[param1].iLastStyle = StringToInt(info);

		DeleteAllStageSubmenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void DeleteAllStageSubmenu(int client)
{
	char sStage[32];
	FormatEx(sStage, sizeof(sStage), "%T %d", "WRStage", client, gA_WRCache[client].iLastStage);

	Menu menu = new Menu(MenuHandler_DeleteAllStage);
	menu.SetTitle("%T\n ", "DeleteAllStageRecordsMenuTitle", client, gS_Map, sStage, gS_StyleStrings[gA_WRCache[client].iLastStyle].sStyleName);

	char sMenuItem[64];

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	FormatEx(sMenuItem, 64, "%T", "MenuResponseYes", client);
	menu.AddItem("yes", sMenuItem);

	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);
}

public int MenuHandler_DeleteAllStage(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);

		if(StringToInt(info) == -1)
		{
			Shavit_PrintToChat(param1, "%T", "DeletionAborted", param1);

			return 0;
		}

		Shavit_LogMessage("%L - deleted all stage %d and %s style records from map `%s`.",
			param1, gA_WRCache[param1].iLastStage, gS_StyleStrings[gA_WRCache[param1].iLastStyle].sStyleName, gS_Map);

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "DELETE FROM %sstagetimes WHERE map = '%s' AND style = %d AND stage = %d;",
			gS_MySQLPrefix, gS_Map, gA_WRCache[param1].iLastStyle, gA_WRCache[param1].iLastStage);

		DataPack hPack = new DataPack();
		hPack.WriteCell(GetClientSerial(param1));
		hPack.WriteCell(gA_WRCache[param1].iLastStyle);
		hPack.WriteCell(gA_WRCache[param1].iLastTrack);
		hPack.WriteCell(gA_WRCache[param1].iLastStage);

		QueryLog(gH_SQL, DeleteAll_Callback, sQuery, hPack, DBPrio_High);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_DeleteAll(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_DeleteAll_First);
	menu.SetTitle("%T\n ", "DeleteTrackAll", client);

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		char sInfo[8];
		IntToString(i, sInfo, 8);

		int iRecords = GetTrackRecordCount(i);

		char sTrack[64];
		GetTrackName(client, i, sTrack, 64);

		if(iRecords > 0)
		{
			Format(sTrack, 64, "%s (%T: %d)", sTrack, "WRRecord", client, iRecords);
		}

		menu.AddItem(sInfo, sTrack, (iRecords > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, 300);

	return Plugin_Handled;
}

public int MenuHandler_DeleteAll_First(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		int iTrack = gA_WRCache[param1].iLastTrack = StringToInt(sInfo);
		gA_WRCache[param1].iLastStage = 0;

		char sTrack[64];
		GetTrackName(param1, iTrack, sTrack, 64);

		Menu subMenu = new Menu(MenuHandler_DeleteAll_Second);
		subMenu.SetTitle("%T\n ", "DeleteTrackAllStyle", param1, sTrack);

		int[] styles = new int[gI_Styles];
		Shavit_GetOrderedStyles(styles, gI_Styles);

		for(int i = 0; i < gI_Styles; i++)
		{
			int iStyle = styles[i];

			if(Shavit_GetStyleSettingInt(iStyle, "enabled") == -1)
			{
				continue;
			}

			char sStyle[64];
			strcopy(sStyle, 64, gS_StyleStrings[iStyle].sStyleName);

			IntToString(iStyle, sInfo, 8);

			int iRecords = GetRecordAmount(iStyle, iTrack);

			if(iRecords > 0)
			{
				Format(sStyle, 64, "%s (%T: %d)", sStyle, "WRRecord", param1, iRecords);
			}

			subMenu.AddItem(sInfo, sStyle, (iRecords > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
		}

		subMenu.ExitButton = true;
		subMenu.Display(param1, 300);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		gH_AdminMenu.DisplayCategory(gH_TimerCommands, param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_DeleteAll_Second(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		gA_WRCache[param1].iLastStyle = StringToInt(sInfo);

		DeleteAllSubmenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void DeleteAllSubmenu(int client)
{
	char sTrack[32];
	GetTrackName(client, gA_WRCache[client].iLastTrack, sTrack, 32);

	Menu menu = new Menu(MenuHandler_DeleteAll);
	menu.SetTitle("%T\n ", "DeleteAllRecordsMenuTitle", client, gS_Map, sTrack, gS_StyleStrings[gA_WRCache[client].iLastStyle].sStyleName);

	char sMenuItem[64];

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	FormatEx(sMenuItem, 64, "%T", "MenuResponseYes", client);
	menu.AddItem("yes", sMenuItem);

	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);
}

public int MenuHandler_DeleteAll(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);

		if(StringToInt(info) == -1)
		{
			Shavit_PrintToChat(param1, "%T", "DeletionAborted", param1);

			return 0;
		}

		char sTrack[32];
		GetTrackName(LANG_SERVER, gA_WRCache[param1].iLastTrack, sTrack, 32);

		Shavit_LogMessage("%L - deleted all %s track and %s style records from map `%s`.",
			param1, sTrack, gS_StyleStrings[gA_WRCache[param1].iLastStyle].sStyleName, gS_Map);

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "DELETE FROM %splayertimes WHERE map = '%s' AND style = %d AND track = %d;",
			gS_MySQLPrefix, gS_Map, gA_WRCache[param1].iLastStyle, gA_WRCache[param1].iLastTrack);

		DataPack hPack = new DataPack();
		hPack.WriteCell(GetClientSerial(param1));
		hPack.WriteCell(gA_WRCache[param1].iLastStyle);
		hPack.WriteCell(gA_WRCache[param1].iLastTrack);
		hPack.WriteCell(gA_WRCache[param1].iLastStage);

		QueryLog(gH_SQL, DeleteAll_Callback, sQuery, hPack, DBPrio_High);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_Delete(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);
		gA_WRCache[param1].iLastStyle = StringToInt(info);

		OpenDelete(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenDelete(int client)
{
	char sQuery[512];

	if(gA_WRCache[client].iLastStage == 0)
	{
		FormatEx(sQuery, 512, 
			"SELECT p.id, u.name, p.time, p.jumps FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE map = '%s' AND style = %d AND track = %d ORDER BY time ASC, date ASC LIMIT 1000;",
			gS_MySQLPrefix, gS_MySQLPrefix, gS_Map, gA_WRCache[client].iLastStyle, gA_WRCache[client].iLastTrack);
	}
	else
	{
		FormatEx(sQuery, 512, 
			"SELECT p.id, u.name, p.time, p.jumps FROM %sstagetimes p JOIN %susers u ON p.auth = u.auth WHERE map = '%s' AND style = %d AND stage = %d ORDER BY time ASC, date ASC LIMIT 1000;", 
			gS_MySQLPrefix, gS_MySQLPrefix, gS_Map, gA_WRCache[client].iLastStyle, gA_WRCache[client].iLastStage);		
	}

	QueryLog(gH_SQL, SQL_OpenDelete_Callback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void SQL_OpenDelete_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR OpenDelete) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	int iStyle = gA_WRCache[client].iLastStyle;
	char sTrack[32];

	if (gA_WRCache[client].iLastStage == 0)
	{
		GetTrackName(client, gA_WRCache[client].iLastTrack, sTrack, sizeof(sTrack));
	}
	else
	{
		FormatEx(sTrack, sizeof(sTrack), "%T %d", "WRStage", client,  gA_WRCache[client].iLastStage);
	}

	Menu menu = new Menu(OpenDelete_Handler);
	menu.SetTitle("%t", "ListClientRecords", gS_Map, sTrack, gS_StyleStrings[iStyle].sStyleName);

	int iCount = 0;

	while(results.FetchRow())
	{
		iCount++;

		// 0 - record id, for statistic purposes.
		int id = results.FetchInt(0);
		char sID[8];
		IntToString(id, sID, 8);

		// 1 - player name
		char sName[MAX_NAME_LENGTH];
		results.FetchString(1, sName, MAX_NAME_LENGTH);
		ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");

		// 2 - time
		float time = results.FetchFloat(2);
		char sTime[16];
		FormatSeconds(time, sTime, 16);

		// 3 - jumps
		int jumps = results.FetchInt(3);

		char sDisplay[128];
		FormatEx(sDisplay, 128, "#%d - %s - %s (%d jump%s)", iCount, sName, sTime, jumps, (jumps != 1)? "s":"");
		menu.AddItem(sID, sDisplay);
	}

	if(iCount == 0)
	{
		char sNoRecords[64];
		FormatEx(sNoRecords, 64, "%T", "WRMapNoRecords", client);
		menu.AddItem("-1", sNoRecords);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);
}

public int OpenDelete_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		int id = StringToInt(sInfo);

		if(id != -1)
		{
			OpenDeleteMenu(param1, id);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenDeleteMenu(int client, int id)
{
	char sMenuItem[64];

	Menu menu = new Menu(DeleteConfirm_Handler);
	menu.SetTitle("%T\n ", "DeleteConfirm", client);

	for(int i = 1; i <= GetRandomInt(1, 4); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	FormatEx(sMenuItem, 64, "%T", "MenuResponseYesSingle", client);

	char sInfo[16];
	IntToString(id, sInfo, 16);
	menu.AddItem(sInfo, sMenuItem);

	for(int i = 1; i <= GetRandomInt(1, 3); i++)
	{
		FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 300);
}

public int DeleteConfirm_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		int iRecordID = StringToInt(sInfo);

		if(iRecordID == -1)
		{
			Shavit_PrintToChat(param1, "%T", "DeletionAborted", param1);
			OpenDelete(param1);

			return 0;
		}

		char sQuery[512];
		if(gA_WRCache[param1].iLastStage == 0)
		{
			FormatEx(sQuery, sizeof(sQuery),
				"SELECT u.auth, u.name, p.map, p.time, p.sync, p.perfs, p.jumps, p.strafes, p.id, p.date, p.style, p.track, "...
				"(SELECT id FROM %splayertimes WHERE style = %d AND track = %d AND map = p.map ORDER BY time, date ASC LIMIT 1) "...
				"FROM %susers u LEFT JOIN %splayertimes p ON u.auth = p.auth WHERE p.id = %d;",
				gS_MySQLPrefix, gA_WRCache[param1].iLastStyle, gA_WRCache[param1].iLastTrack, gS_MySQLPrefix, gS_MySQLPrefix, iRecordID);			
		}
		else
		{
			FormatEx(sQuery, sizeof(sQuery),
				"SELECT u.auth, u.name, p.map, p.time, p.sync, p.perfs, p.jumps, p.strafes, p.id, p.date, p.style, p.track, p.stage,"...
				"(SELECT id FROM %sstagetimes WHERE style = %d AND stage = %d AND map = p.map ORDER BY time, date ASC LIMIT 1) "...
				"FROM %susers u LEFT JOIN %sstagetimes p ON u.auth = p.auth WHERE p.id = %d;",
				gS_MySQLPrefix, gA_WRCache[param1].iLastStyle, gA_WRCache[param1].iLastStage, gS_MySQLPrefix, gS_MySQLPrefix, iRecordID);
		}

		QueryLog(gH_SQL, GetRecordDetails_Callback, sQuery, GetClientSerial(param1), DBPrio_High);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void GetRecordDetails_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientFromSerial(data);
	
	if(results == null)
	{
		OpenDelete(client);
		LogError("Timer (WR GetRecordDetails) SQL query failed. Reason: %s", error);
		
		return;
	}

	if(results.FetchRow())
	{
		int iSteamID = results.FetchInt(0);

		char sName[MAX_NAME_LENGTH];
		results.FetchString(1, sName, MAX_NAME_LENGTH);

		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(2, sMap, sizeof(sMap));

		float fTime = results.FetchFloat(3);
		float fSync = results.FetchFloat(4);
		float fPerfectJumps = results.FetchFloat(5);

		int iJumps = results.FetchInt(6);
		int iStrafes = results.FetchInt(7);
		int iRecordID = results.FetchInt(8);
		int iTimestamp = results.FetchInt(9);
		int iStyle = results.FetchInt(10);
		int iTrack = results.FetchInt(11);	
		int iStage = 0;
		int iWRRecordID;
		

		if(gA_WRCache[client].iLastStage > 0)
		{
			iStage = results.FetchInt(12);
			iWRRecordID = results.FetchInt(13);
		}
		else
		{
			iWRRecordID = results.FetchInt(12);
		}

		// that's a big datapack ya yeet
		DataPack hPack = new DataPack();
		hPack.WriteCell(GetSteamAccountID(client));
		hPack.WriteCell(iSteamID);
		hPack.WriteString(sName);
		hPack.WriteString(sMap);
		hPack.WriteCell(fTime);
		hPack.WriteCell(fSync);
		hPack.WriteCell(fPerfectJumps);
		hPack.WriteCell(iJumps);
		hPack.WriteCell(iStrafes);
		hPack.WriteCell(iRecordID);
		hPack.WriteCell(iTimestamp);
		hPack.WriteCell(iStyle);
		hPack.WriteCell(iTrack);
		hPack.WriteCell(iStage);

		bool bWRDeleted = iWRRecordID == iRecordID;
		hPack.WriteCell(bWRDeleted);

		char sQuery[256];
		if(iStage == 0)
		{
			FormatEx(sQuery, 256, "DELETE FROM %splayertimes WHERE id = %d;",
				gS_MySQLPrefix, iRecordID);
			QueryLog(gH_SQL, DeleteConfirm_Callback, sQuery, hPack, DBPrio_High);
			
			//Delete stage pb as well
			FormatEx(sQuery, sizeof(sQuery),
				"DELETE FROM `%scptimes` WHERE style = %d AND track = %d AND map = '%s' AND auth = %d;",
				gS_MySQLPrefix, iStyle, iTrack, gS_Map, iSteamID);
			
			QueryLog(gH_SQL, DeleteConfirm_DeleteCPPB_Callback, sQuery, 0, DBPrio_High);
		}
		else
		{
			FormatEx(sQuery, 256, "DELETE FROM %sstagetimes WHERE id = %d;",
				gS_MySQLPrefix, iRecordID);
			QueryLog(gH_SQL, DeleteConfirm_Callback, sQuery, hPack, DBPrio_High);
		}
	}
}

public void DeleteConfirm_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	hPack.Reset();

	int admin_steamid = hPack.ReadCell();
	int iSteamID = hPack.ReadCell();

	char sName[MAX_NAME_LENGTH];
	hPack.ReadString(sName, MAX_NAME_LENGTH);

	char sMap[PLATFORM_MAX_PATH];
	hPack.ReadString(sMap, sizeof(sMap));

	float fTime = view_as<float>(hPack.ReadCell());
	float fSync = view_as<float>(hPack.ReadCell());
	float fPerfectJumps = view_as<float>(hPack.ReadCell());

	int iJumps = hPack.ReadCell();
	int iStrafes = hPack.ReadCell();
	int iRecordID = hPack.ReadCell();
	int iTimestamp = hPack.ReadCell();
	int iStyle = hPack.ReadCell();
	int iTrack = hPack.ReadCell();
	int iStage = hPack.ReadCell();

	bool bWRDeleted = view_as<bool>(hPack.ReadCell());
	delete hPack;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && GetSteamAccountID(i) == admin_steamid)
		{
			if (iStage == 0)
			{
				DeleteSubmenu(i);				
			}
			else
			{
				Command_DeleteStageRecord(i, 0);
			}

			break;
		}
	}

	if(results == null)
	{
		LogError("Timer (WR DeleteConfirm) SQL query failed. Reason: %s", error);

		return;
	}

	if(bWRDeleted)	//If delete a record is WR (SR)
	{
		if(iStage == 0)
		{
			DeleteWR(iStyle, iTrack, sMap, iSteamID, iRecordID, false, true);			
		}
		else
		{
			DeleteStageWR(iStyle, iTrack, iStage, sMap, iSteamID, iRecordID, false, true);
		}
	}
	else	//IF Not Run into this
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsValidClient(i) && GetSteamAccountID(i) == iSteamID)
			{
				UpdateClientCache(i);
				break;
			}
		}
	}

	char sTrack[32];
	GetTrackName(LANG_SERVER, iTrack, sTrack, 32);
	
	char sStage[32];
	FormatEx(sStage, sizeof(sStage), "| Stage: %d ", iStage);

	char sDate[32];
	FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", iTimestamp);

	// above the client == 0 so log doesn't get lost if admin disconnects between deleting record and query execution
	Shavit_LogMessage("Admin [U:1:%u] - deleted %srecord. Runner: %s ([U:1:%u]) | Map: %s | Style: %s | Track: %s %s| Time: %.2f (%s) | Strafes: %d (%.1f%%) | Jumps: %d (%.1f%%) | Run date: %s | Record ID: %d",
		admin_steamid, (iStage == 0) ? "":"stage ", sName, iSteamID, sMap, gS_StyleStrings[iStyle].sStyleName, sTrack, (iStage == 0) ? "":sStage, fTime, (bWRDeleted)? "WR":"not WR", iStrafes, fSync, iJumps, fPerfectJumps, sDate, iRecordID);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i) && GetSteamAccountID(i) == admin_steamid)
		{
			Shavit_PrintToChat(i, "%T", "DeletedRecord", i);
			break;
		}
	}
}

public void DeleteConfirm_DeleteCPPB_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	if(results == null)
	{
		LogError("Timer (WR DeleteConfirm) SQL query failed. Reason: %s", error);

		return;
	}
}

public void DeleteAll_Callback(Database db, DBResultSet results, const char[] error, DataPack hPack)
{
	hPack.Reset();
	int client = GetClientFromSerial(hPack.ReadCell());
	int style = hPack.ReadCell();
	int track = hPack.ReadCell();
	int stage = hPack.ReadCell();
	delete hPack;

	if(results == null)
	{
		LogError("Timer (WR DeleteAll%s) SQL query failed. Reason: %s", stage == 0 ? "":"Stage", error);

		return;
	}

	if(stage == 0)
	{
		DeleteWR(style, track, gS_Map, 0, -1, false, true);		
		Shavit_PrintToChat(client, "%T", "DeletedRecordsMap", client, gS_ChatStrings.sVariable, gS_Map, gS_ChatStrings.sText);
	}
	else if(stage > 0)
	{
		DeleteStageWR(style, track, stage, gS_Map, 0, -1, false, true);
		Shavit_PrintToChat(client, "%T", "DeletedRecordsMap", client, gS_ChatStrings.sVariable, gS_Map, gS_ChatStrings.sText);
	}
}


public Action Command_WorldRecord_Style(int client, int args)
{
	char sCommand[128];
	GetCmdArg(0, sCommand, sizeof(sCommand));

	int style = 0;

	if (gSM_StyleCommands.GetValue(sCommand, style))
	{
		gA_WRCache[client].bForceStyle = true;
		gA_WRCache[client].iLastStyle = style;
		Command_WorldRecord(client, args);
	}

	return Plugin_Handled;
}

public Action Command_WorldRecord(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	int track = Track_Main;
	int stage = 0;
	bool havemap = false;

	if(StrContains(sCommand, "sm_b", false) == 0)
	{
		if (args >= 1)
		{
			char arg[6];
			GetCmdArg((args > 1) ? 2 : 1, arg, sizeof(arg));
			track = StringToInt(arg);

			// if the track doesn't fit in the bonus track range then assume it's a map name
			if (args > 1 || (track < Track_Bonus || track > Track_Bonus_Last))
			{
				havemap = true;
			}

			if (track < Track_Bonus || track > Track_Bonus_Last)
			{
				track = Track_Bonus;
			}			
		}
		else
		{
			track = -1;
		}
	}
	else if(StrEqual(sCommand, "sm_wrcp", false) || StrContains(sCommand, "sm_cp", false) == 0 || StrContains(sCommand, "sm_s", false) == 0)
	{
		if (args >= 1)
		{
			char arg[6];
			GetCmdArg((args > 1) ? 2 : 1, arg, sizeof(arg));	// only 1 args, read that as stage number, else first one is map name second one is stage num.
			stage = StringToInt(arg);

			// if the track doesn't fit in the max stage range then assume it's a map name
			if (args > 1 || stage < 1 || stage > MAX_STAGES)
			{
				havemap = true;
			}
		}

		if (stage == 0)	// if the fucking args is 1 and its not a number, the stage will assign to 0. :(
		{
			stage = -1;
		}
	}
	else
	{
		havemap = (args >= 1);
	}

	gA_WRCache[client].iLastStage = stage;
	gA_WRCache[client].iLastTrack = track;

	if(!havemap)	// no map argument
	{
		gA_WRCache[client].sClientMap = gS_Map;
	}
	else
	{
		GetCmdArg(1, gA_WRCache[client].sClientMap, sizeof(wrcache_t::sClientMap));
		LowercaseString(gA_WRCache[client].sClientMap);

		Menu wrmatches = new Menu(WRMatchesMenuHandler);
		wrmatches.SetTitle("%T", "Choose Map", client);

		int length = gA_ValidMaps.Length;
		for (int i = 0; i < length; i++)
		{
			char entry[PLATFORM_MAX_PATH];
			gA_ValidMaps.GetString(i, entry, PLATFORM_MAX_PATH);

			if (StrContains(entry, gA_WRCache[client].sClientMap) != -1)
			{
				wrmatches.AddItem(entry, entry);
			}
		}

		switch (wrmatches.ItemCount)
		{
			case 0:
			{
				delete wrmatches;
				Shavit_PrintToChat(client, "%t", "Map was not found", gA_WRCache[client].sClientMap);
				return Plugin_Handled;
			}
			case 1:
			{
				wrmatches.GetItem(0, gA_WRCache[client].sClientMap, sizeof(wrcache_t::sClientMap));
				delete wrmatches;
			}
			default:
			{
				wrmatches.Display(client, MENU_TIME_FOREVER);
				return Plugin_Handled;
			}
		}
	}
	
	RetrieveWRMenu(client, track, stage);
	return Plugin_Handled;
}

public int WRMatchesMenuHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char map[PLATFORM_MAX_PATH];
		menu.GetItem(param2, map, sizeof(map));
		gA_WRCache[param1].sClientMap = map;

		RetrieveWRMenu(param1, gA_WRCache[param1].iLastTrack, gA_WRCache[param1].iLastStage);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void RetrieveWRMenu(int client, int track, int stage = 0)
{
	if (gA_WRCache[client].bPendingMenu)
	{
		return;
	}

	if (stage == 0)
	{
		if(track >= 0)
		{
			if (StrEqual(gA_WRCache[client].sClientMap, gS_Map))
			{
				for (int i = 0; i < gI_Styles; i++)
				{
					gA_WRCache[client].fWRs[i] = gF_WRTime[i][track];
				}

				if (gA_WRCache[client].bForceStyle)
				{
					StartWRMenu(client);
				}
				else
				{
					ShowWRStyleMenu(client);
				}
			}
			else
			{
				gA_WRCache[client].bPendingMenu = true;
				char sQuery[512];
				FormatEx(sQuery, sizeof(sQuery),
					"SELECT style, time FROM %swrs WHERE map = '%s' AND track = %d AND style < %d ORDER BY style;",
					gS_MySQLPrefix, gA_WRCache[client].sClientMap, track, gI_Styles);
				QueryLog(gH_SQL, SQL_RetrieveWRMenu_Callback, sQuery, GetClientSerial(client));
			}
		}
		else
		{
			int iTrackMask = Shavit_GetMapTracks(false, true);

			Menu selectbonus = new Menu(MenuHandler_WRSelectBonus);
			selectbonus.SetTitle("%T", "WRMenuBonusTitle", client);
			char sTrack[32];

			for(int i = Track_Bonus; i < TRACKS_SIZE; i++)
			{
				if(iTrackMask < 0)
				{
					break;
				}
				
				if (((iTrackMask >> i) & 1) == 1)
				{
					GetTrackName(client, i, sTrack, sizeof(sTrack));
					
					char sInfo[8];
					IntToString(i, sInfo, 8);

					selectbonus.AddItem(sInfo, sTrack, ITEMDRAW_DEFAULT);
				}
			}

			if(selectbonus.ItemCount == 0)
			{
				delete selectbonus;
				return;
			}

			selectbonus.Display(client, MENU_TIME_FOREVER);
			return;
		}
	}
	else if (stage < 0)
	{
		int iStageCount = Shavit_GetStageCount(Track_Main);

		if(iStageCount == 0)
		{
			return;
		}

		Menu selectstage = new Menu(MenuHandler_WRSelectStage);
		selectstage.SetTitle("%T", "WRMenuStageTitle", client);
		char sSelection[4];
		char sMenu[16];

		for(int i = 1; i < iStageCount; i++)
		{
			IntToString(i, sSelection, sizeof(sSelection));
			FormatEx(sMenu, sizeof(sMenu), "%T %d", "WRStage", client, i);
			selectstage.AddItem(sSelection, sMenu);
		}

		selectstage.Display(client, MENU_TIME_FOREVER);
		return;
	}
	else
	{
		if (StrEqual(gA_WRCache[client].sClientMap, gS_Map))
		{
			for (int i = 0; i < gI_Styles; i++)
			{
				gA_WRCache[client].fWRs[i] = gF_StageWRTime[i][stage];
			}

			if (gA_WRCache[client].bForceStyle)
			{
				StartWRMenu(client);
			}
			else
			{
				ShowWRStyleMenu(client);
			}
		}
		else
		{
			gA_WRCache[client].bPendingMenu = true;
			char sQuery[512];
			FormatEx(sQuery, sizeof(sQuery),
				"SELECT style, time FROM %sstagewrs WHERE map = '%s' AND stage = %d AND track = %d AND style < %d ORDER BY style;",
				gS_MySQLPrefix, gA_WRCache[client].sClientMap, stage, track, gI_Styles);
			QueryLog(gH_SQL, SQL_RetrieveWRMenu_Callback, sQuery, GetClientSerial(client));
		}
	}
}

public int MenuHandler_WRSelectBonus(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sTrack[4];
		menu.GetItem(param2, sTrack, sizeof(sTrack));
		gA_WRCache[param1].iLastTrack = StringToInt(sTrack);

		RetrieveWRMenu(param1, gA_WRCache[param1].iLastTrack, gA_WRCache[param1].iLastStage);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_WRSelectStage(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char sStage[4];
		menu.GetItem(param2, sStage, sizeof(sStage));
		gA_WRCache[param1].iLastStage = StringToInt(sStage);

		RetrieveWRMenu(param1, gA_WRCache[param1].iLastTrack, gA_WRCache[param1].iLastStage);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void SQL_RetrieveWRMenu_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR RetrieveWRMenu) SQL query failed. Reason: %s", error);
		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	gA_WRCache[client].bPendingMenu = false;

	for (int i = 0; i < gI_Styles; i++)
	{
		gA_WRCache[client].fWRs[i] = 0.0;
	}

	while (results.FetchRow())
	{
		int style  = results.FetchInt(0);
		float time = results.FetchFloat(1);
		gA_WRCache[client].fWRs[style] = time;
	}

	if (gA_WRCache[client].bForceStyle)
	{
		StartWRMenu(client);
	}
	else
	{
		ShowWRStyleMenu(client);
	}	
}

void ShowWRStyleMenu(int client, int first_item=0)
{
	Menu menu = new Menu(MenuHandler_StyleChooser);
	menu.SetTitle("%T", "WRMenuTitle", client);

	int[] styles = new int[gI_Styles];
	Shavit_GetOrderedStyles(styles, gI_Styles);

	for(int i = 0; i < gI_Styles; i++)
	{
		int iStyle = styles[i];

		if(Shavit_GetStyleSettingInt(iStyle, "unranked") || Shavit_GetStyleSettingInt(iStyle, "enabled") == -1)
		{
			continue;
		}

		char sInfo[8];
		IntToString(iStyle, sInfo, 8);

		char sDisplay[64];

		if (gA_WRCache[client].fWRs[iStyle] > 0.0)
		{
			char sTime[32];
			FormatSeconds(gA_WRCache[client].fWRs[iStyle], sTime, 32, false);

			FormatEx(sDisplay, 64, "%s - WR: %s", gS_StyleStrings[iStyle].sStyleName, sTime);
		}
		else
		{
			strcopy(sDisplay, 64, gS_StyleStrings[iStyle].sStyleName);
		}

		menu.AddItem(sInfo, sDisplay, (gA_WRCache[client].fWRs[iStyle] > 0.0) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	// should NEVER happen
	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "WRStyleNothing", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.DisplayAt(client, first_item, MENU_TIME_FOREVER);
}

public int MenuHandler_StyleChooser(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!IsValidClient(param1))
		{
			return 0;
		}
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		int iStyle = StringToInt(sInfo);

		if(iStyle == -1)
		{
			Shavit_PrintToChat(param1, "%T", "NoStyles", param1, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

			return 0;
		}

		gA_WRCache[param1].iLastStyle = iStyle;
		gA_WRCache[param1].iPagePosition = GetMenuSelectionPosition();

		StartWRMenu(param1);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void StartWRMenu(int client)
{
	gA_WRCache[client].bForceStyle = false;

	DataPack dp = new DataPack();
	dp.WriteCell(GetClientSerial(client));
	dp.WriteCell(gA_WRCache[client].iLastTrack);
	dp.WriteCell(gA_WRCache[client].iLastStage);
	dp.WriteString(gA_WRCache[client].sClientMap);

	int iLength = ((strlen(gA_WRCache[client].sClientMap) * 2) + 1);
	char[] sEscapedMap = new char[iLength];
	gH_SQL.Escape(gA_WRCache[client].sClientMap, sEscapedMap, iLength);

	char sQuery[512];
	if(gA_WRCache[client].iLastStage == 0)
	{
		FormatEx(sQuery, 512, 
			"SELECT p.id, u.name, p.time, p.auth FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE map = '%s' AND style = %d AND track = %d ORDER BY time ASC, date ASC;", 
			gS_MySQLPrefix, gS_MySQLPrefix, sEscapedMap, gA_WRCache[client].iLastStyle, gA_WRCache[client].iLastTrack);
	}
	else
	{
		FormatEx(sQuery, 512, 
			"SELECT p.id, u.name, p.time, p.auth FROM %sstagetimes p JOIN %susers u ON p.auth = u.auth WHERE map = '%s' AND style = %d AND track = %d AND stage = %d ORDER BY time ASC, date ASC;", 
			gS_MySQLPrefix, gS_MySQLPrefix, sEscapedMap, gA_WRCache[client].iLastStyle, gA_WRCache[client].iLastTrack, gA_WRCache[client].iLastStage);		
	}
	QueryLog(gH_SQL, SQL_WR_Callback, sQuery, dp);
}

public void SQL_WR_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int serial = data.ReadCell();
	int track = data.ReadCell();
	int stage = data.ReadCell();

	char sMap[PLATFORM_MAX_PATH];
	data.ReadString(sMap, sizeof(sMap));

	delete data;

	if(results == null)
	{
		LogError("Timer (WR SELECT) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(serial);
	
	if(client == 0)
	{
		return;
	}

	int iSteamID = GetSteamAccountID(client);

	Menu hMenu = new Menu(WRMenu_Handler);

	int iCount = 0;
	int iMyRank = 0;
	float fWR = 0.0;

	while(results.FetchRow())
	{
		if(++iCount <= gCV_RecordsLimit.IntValue)
		{
			// 0 - record id, for statistic purposes.
			int id = results.FetchInt(0);
			char sID[8];
			IntToString(id, sID, 8);

			// 1 - player name
			char sName[MAX_NAME_LENGTH];
			results.FetchString(1, sName, MAX_NAME_LENGTH);

			// 2 - time
			float time = results.FetchFloat(2);
			
			if(iCount == 1)
			{
				fWR = time;
			}

			char sTime[16];
			FormatSeconds(time, sTime, 16);

			// 3 - time diff
			float diff = time - fWR;
			char sDiff[32];
			if (diff < 60.0)
			{
				FormatSeconds(diff, sDiff, 32);
			}
			else
			{
				FormatSeconds(diff, sDiff, 32, false, true);
			}

			char sDisplay[128];
			FormatEx(sDisplay, 128, "#%d\t|\t\t\t%s (+%s) \t\t\t\t\t%s ", iCount, sTime, sDiff, sName);
			hMenu.AddItem(sID, sDisplay);
		}

		// check if record exists in the map's top X
		int iQuerySteamID = results.FetchInt(3);

		if(iQuerySteamID == iSteamID)
		{
			iMyRank = iCount;
		}
	}

	char sFormattedTitle[256];

	if(hMenu.ItemCount == 0)
	{
		hMenu.SetTitle("%T", "WRMap", client, sMap);
		char sNoRecords[64];
		FormatEx(sNoRecords, 64, "%T", "WRMapNoRecords", client);

		hMenu.AddItem("-1", sNoRecords);
	}
	else
	{
		int iRecords = results.RowCount;

		// [32] just in case there are 150k records on a map and you're ranked 100k or something
		char sRanks[32];

		if(iMyRank == 0)
		{
			FormatEx(sRanks, 32, "(%d %T)", iRecords, "WRRecord", client);
		}
		else
		{
			FormatEx(sRanks, 32, "(#%d/%d)", iMyRank, iRecords);
		}

		char sTrack[32];
		if(stage == 0)
		{
			GetTrackName(client, track, sTrack, 32);
		}
		else
		{
			FormatEx(sTrack, sizeof(sTrack), "%T %d", "WRStage", client, stage);
		}	

		FormatEx(sFormattedTitle, 192, "%T\n%s", "WRRecordFor", client, sMap, sTrack, sRanks);
		hMenu.SetTitle(sFormattedTitle);
	}

	hMenu.ExitBackButton = true;
	hMenu.Display(client, 300);
}

public int WRMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);
		int id = StringToInt(sInfo);

		if(id != -1)
		{
			OpenSubMenu(param1, id, gA_WRCache[param1].iLastStage);
		}
		else
		{
			ShowWRStyleMenu(param1);
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowWRStyleMenu(param1, gA_WRCache[param1].iPagePosition);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_RecentRecords(int client, int args)
{
	if(gA_WRCache[client].bPendingMenu || !IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(RRFirstMenu_Handler);
	menu.SetTitle("%T\n ", "RecentRecordsFirstMenuTitle", client);

	char display[256];
	FormatEx(display, sizeof(display), "%T", "RecentRecordsAll", client);
	menu.AddItem("all", display, (gB_RRSelectMain[client] || gB_RRSelectBonus[client] || gB_RRSelectStage[client]) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	FormatEx(display, sizeof(display), "%T\n ", "RecentRecordsByStyle", client);
	menu.AddItem("style", display, (gB_RRSelectMain[client] || gB_RRSelectBonus[client] || gB_RRSelectStage[client]) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	FormatEx(display, sizeof(display), "%T", "RecentRecordsSelectMain", client, gB_RRSelectMain[client] ? "＋":"－");
	menu.AddItem("selectmain", display);
	FormatEx(display, sizeof(display), "%T", "RecentRecordsSelectBonus", client, gB_RRSelectBonus[client] ? "＋":"－");
	menu.AddItem("selectbonus", display);
	FormatEx(display, sizeof(display), "%T", "RecentRecordsSelectStage", client, gB_RRSelectStage[client] ? "＋":"－");
	menu.AddItem("selectstage", display);

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int RRFirstMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		int client = param1;
		char info[16];
		menu.GetItem(param2, info, sizeof(info));

		if (StrEqual(info, "all"))
		{
			RecentRecords_DoQuery(client, "");
		}
		else if (StrEqual(info, "style"))
		{
			RecentRecords_StyleMenu(client);
		}
		else if (StrEqual(info, "selectmain"))
		{
			gB_RRSelectMain[client] = !gB_RRSelectMain[client];
			Command_RecentRecords(client, 0); // remake menu...
		}
		else if (StrEqual(info, "selectbonus"))
		{
			gB_RRSelectBonus[client] = !gB_RRSelectBonus[client];
			Command_RecentRecords(client, 0); // remake menu...
		}
		else if (StrEqual(info, "selectstage"))
		{
			gB_RRSelectStage[client] = !gB_RRSelectStage[client];
			Command_RecentRecords(client, 0); // remake menu...
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void RecentRecords_StyleMenu(int client)
{
	Menu menu = new Menu(RRStyleSelectionMenu_Handler);
	menu.SetTitle("%T\n ", "RecentRecordsStyleSelectionMenuTitle", client);

	int[] styles = new int[gI_Styles];
	Shavit_GetOrderedStyles(styles, gI_Styles);

	for (int i = 0; i < gI_Styles; i++)
	{
		int style = styles[i];

		if (Shavit_GetStyleSettingInt(style, "enabled") == -1)
		{
			continue;
		}

		char info[8];
		IntToString(style, info, sizeof(info));

		menu.AddItem(info, gS_StyleStrings[style].sStyleName);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int RRStyleSelectionMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, sizeof(info));
		RecentRecords_DoQuery(param1, info);
	}
	else if (action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Command_RecentRecords(param1, 0);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void RecentRecords_DoQuery(int client, char[] style)
{
	char sQuery[2048];

	char sQuery1[512];
	FormatEx(sQuery1, sizeof(sQuery1), "SELECT a.id, a.map, u.name, a.time, a.style, a.track, 0 as stage, a.date FROM %swrs a JOIN %susers u on a.auth = u.auth WHERE a.track %s %s %s %s",
		gS_MySQLPrefix, gS_MySQLPrefix,
		(gB_RRSelectMain[client] && gB_RRSelectBonus[client]) ? "> -1" : (!gB_RRSelectMain[client]) ? "> 0":"= 0", 
		(style[0] != '\0') ? "AND" : "",
		(style[0] != '\0') ? "a.style = " : "",
		(style[0] != '\0') ? style : "");

	char sQuery2[512];
	FormatEx(sQuery2, sizeof(sQuery2), " %s SELECT b.id, b.map, u.name, b.time, b.style, b.track, b.stage, b.date FROM %sstagewrs b JOIN %susers u on b.auth = u.auth %s %s",
		(gB_RRSelectMain[client] || gB_RRSelectBonus[client]) ? "UNION":"",
		gS_MySQLPrefix, gS_MySQLPrefix,
		(style[0] != '\0') ? "WHERE b.style = " : "",
		(style[0] != '\0') ? style : "");

	FormatEx(sQuery, sizeof(sQuery2), "SELECT * FROM ( %s %s ) c ORDER BY c.date DESC LIMIT %d;",
	(gB_RRSelectMain[client] || gB_RRSelectBonus[client]) ? sQuery1:"", gB_RRSelectStage[client] ? sQuery2:"",
	gCV_RecentLimit.IntValue);

	QueryLog(gH_SQL, SQL_RR_Callback, sQuery, GetClientSerial(client), DBPrio_Low);

	gA_WRCache[client].bPendingMenu = true;
}


public void SQL_RR_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientFromSerial(data);

	gA_WRCache[client].bPendingMenu = false;

	if(results == null)
	{
		LogError("Timer (RR SELECT) SQL query failed. Reason: %s", error);

		return;
	}

	if(client == 0)
	{
		return;
	}

	Menu menu = new Menu(RRMenu_Handler);
	menu.SetTitle("%T:", "RecentRecords", client, gCV_RecentLimit.IntValue);

	while(results.FetchRow())
	{
		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(1, sMap, sizeof(sMap));

		char sName[MAX_NAME_LENGTH];
		results.FetchString(2, sName, sizeof(sName));
		TrimDisplayString(sName, sName, sizeof(sName), 9);

		char sTime[16];
		float fTime = results.FetchFloat(3);
		FormatSeconds(fTime, sTime, 16);

		int iStyle = results.FetchInt(4);
		if(iStyle >= gI_Styles || iStyle < 0 || Shavit_GetStyleSettingInt(iStyle, "unranked"))
		{
			continue;
		}

		int track = results.FetchInt(5);
		int stage = results.FetchInt(6);

		char sTrack[32];

		if(stage == 0)
		{
			GetTrackName(client, track, sTrack, 32);
		}
		else
		{
			FormatEx(sTrack, sizeof(sTrack), "%T %d", "WRStage", client, stage);
		}

		char sDisplay[192];
		FormatEx(sDisplay, 192, "[%s/%s] %s - %s @ %s", gS_StyleStrings[iStyle].sShortName, sTrack, sMap, sName, sTime);

		char sInfo[192];
		FormatEx(sInfo, 192, "%d;%d;%s", stage, results.FetchInt(0), sMap);

		menu.AddItem(sInfo, sDisplay);
	}

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "WRMapNoRecords", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int RRMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[128];
		menu.GetItem(param2, sInfo, 128);

		if(StringToInt(sInfo) != -1)
		{
			char sExploded[3][128];
			ExplodeString(sInfo, ";", sExploded, 3, 128, true);

			strcopy(gA_WRCache[param1].sClientMap, 128, sExploded[1]);

			OpenSubMenu(param1, StringToInt(sExploded[1]), StringToInt(sExploded[0]));
		}
		else
		{
			RetrieveWRMenu(param1, gA_WRCache[param1].iLastTrack);
		}
	}
	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		Command_RecentRecords(param1, 0);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_PersonalBest(int client, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char map[PLATFORM_MAX_PATH];
	int steamid = 0;

	char arg[256];
	char name[MAX_NAME_LENGTH];

	if (args > 0) // map || player || player & map
	{
		GetCmdArg(1, arg, sizeof(arg));
		steamid = SteamIDToAccountID(arg);

		if (steamid)
		{
			strcopy(name, sizeof(name), arg);
		}
		else // not a steamid, so check if it's an ingame player
		{
			// FindTarget but without error message, taken from helper.inc
			int target_list[1];
			int flags = COMMAND_FILTER_NO_MULTI | COMMAND_FILTER_NO_BOTS;
			char target_name[MAX_TARGET_LENGTH];
			bool tn_is_ml;

			// Not a player, showing our own pbs on specified map
			if (ProcessTargetString(arg, client, target_list, 1, flags, target_name, sizeof(target_name), tn_is_ml) != 1)
			{
				map = arg;
			}
			else
			{
				if (!(steamid = GetSteamAccountID(target_list[0])))
				{
					Shavit_PrintToChat(client, "%T", "No matching client", client);
					return Plugin_Handled;
				}

				GetClientName(target_list[0], name, sizeof(name));
			}
		}
	}

	if (args >= 2) // player & map
	{
		if (!steamid)
		{
			Shavit_PrintToChat(client, "%T", "No matching client", client);
			return Plugin_Handled;
		}

		GetCmdArg(2, map, sizeof(map));
	}
	else if (args == 1) // map || player
	{
		if (steamid == 0) // must be a map
		{
			map = arg;
		}
	}

	LowercaseString(map);
	TrimString(map);

	if (!steamid)
	{
		steamid = GetSteamAccountID(client);
		GetClientName(client, name, sizeof(name));
	}

	if (!map[0])
	{
		strcopy(map, sizeof(map), gS_Map);
	}

	char validmap[PLATFORM_MAX_PATH];
	int length = gA_ValidMaps.Length;
	for (int i = 0; i < length; i++)
	{
		char entry[PLATFORM_MAX_PATH];
		gA_ValidMaps.GetString(i, entry, PLATFORM_MAX_PATH);

		if (StrEqual(entry, map))
		{
			validmap = map;
			break;
		}

		if (!validmap[0] && StrContains(entry, map) != -1)
		{
			validmap = entry;
		}
	}

	if (!validmap[0])
	{
		Shavit_PrintToChat(client, "%T", "Map was not found", client, map);
		return Plugin_Handled;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(client));
	pack.WriteString(validmap);
	pack.WriteString(name);

	char query[512];
	FormatEx(query, sizeof(query), 
	"SELECT p.id, p.style, p.track, 0 as stage, p.time, p.date, u.name FROM %splayertimes p JOIN %susers u ON p.auth = u.auth WHERE p.auth = %d AND p.map = '%s' UNION ALL "...
	"SELECT s.id, s.style, s.track, s.stage, s.time, s.date, u.name FROM %sstagetimes s JOIN %susers u ON s.auth = u.auth WHERE s.auth = %d AND s.map = '%s' ORDER BY s.stage, p.track, s.style;",
	gS_MySQLPrefix, gS_MySQLPrefix, steamid, validmap, gS_MySQLPrefix, gS_MySQLPrefix, steamid, validmap);

	QueryLog(gH_SQL, SQL_PersonalBest_Callback, query, pack, DBPrio_Low);

	return Plugin_Handled;
}

public void SQL_PersonalBest_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int client = GetClientFromSerial(data.ReadCell());
	char map[PLATFORM_MAX_PATH];
	data.ReadString(map, sizeof(map));
	char name[MAX_NAME_LENGTH];
	data.ReadString(name, sizeof(name));
	delete data;

	if(results == null)
	{
		LogError("Timer (SQL_PersonalBest_Callback) error! Reason: %s", error);
		return;
	}

	if (client == 0)
	{
		return;
	}

	if (!results.RowCount)
	{
		Shavit_PrintToChat(client, "%T", "NoPB", client, gS_ChatStrings.sVariable, name, gS_ChatStrings.sText, gS_ChatStrings.sVariable, map, gS_ChatStrings.sText);
		return;
	}

	name[0] = 0; // i want the name from the users table...

	Menu menu = new Menu(PersonalBestMenu_Handler);

	while (results.FetchRow())
	{
		int id = results.FetchInt(0);
		int style = results.FetchInt(1);
		int track = results.FetchInt(2);
		int stage = results.FetchInt(3);
		float time = results.FetchFloat(4);
		char date[32];
		FormatTime(date, sizeof(date), "%Y-%m-%d %H:%M:%S", results.FetchInt(5));

		if (!name[0])
		{
			results.FetchString(6, name, sizeof(name));
		}

		char track_name[32];

		if(stage == 0)
		{
			GetTrackName(client, track, track_name, sizeof(track_name));			
		}
		else
		{
			FormatEx(track_name, sizeof(track_name), "%T %d", "WRStage", client, stage);
		}

		char formated_time[32];
		FormatSeconds(time, formated_time, sizeof(formated_time));

		char display[256];
		Format(display, sizeof(display), "%s - %s - %s", track_name, gS_StyleStrings[style].sStyleName, formated_time);

		char info[16];
		IntToString(id, info, sizeof(info));
		menu.AddItem(info, display);
	}

	menu.SetTitle("%T", "ListPersonalBest", client, name, map);

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	delete gH_PBMenu[client];
	gH_PBMenu[client] = menu;
}

public int PersonalBestMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, sizeof(info));
		gI_PBMenuPos[param1] = GetMenuSelectionPosition();
		int record_id = StringToInt(info);
		OpenSubMenu(param1, record_id);
	}
	else if(action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_Exit)
		{
			delete gH_PBMenu[param1];
		}
	}
#if 0
	else if (action == MenuAction_End)
	{
		delete menu;
	}
#endif

	return 0;
}

void OpenSubMenu(int client, int id, int stage = 0)
{
	char sQuery[512];
	FormatEx(sQuery, 512,
		"SELECT u.name, p.time, p.jumps, p.style, u.auth, p.date, p.map, p.strafes, p.sync, p.perfs, p.points, p.track, %sstage, p.completions FROM %s%s p JOIN %susers u ON p.auth = u.auth WHERE p.id = %d LIMIT 1;",
		stage > 0 ? "p.":"0 AS ", gS_MySQLPrefix, stage > 0 ? "stagetimes":"playertimes", gS_MySQLPrefix, id);

	DataPack datapack = new DataPack();
	datapack.WriteCell(GetClientSerial(client));
	datapack.WriteCell(id);

	QueryLog(gH_SQL, SQL_SubMenu_Callback, sQuery, datapack, DBPrio_High);
}

public void SQL_SubMenu_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int client = GetClientFromSerial(data.ReadCell());
	int id = data.ReadCell();
	delete data;

	if(results == null)
	{
		delete gH_PBMenu[client];
		LogError("Timer (WR SUBMENU) SQL query failed. Reason: %s", error);

		return;
	}

	if(client == 0)
	{
		return;
	}

	Menu hMenu = new Menu(SubMenu_Handler);

	char sFormattedTitle[256];
	char sName[MAX_NAME_LENGTH];
	int iSteamID = 0;
	char sTrack[32];
	char sMap[PLATFORM_MAX_PATH];

	if(results.FetchRow())
	{
		int stage = results.FetchInt(12);
		results.FetchString(0, sName, MAX_NAME_LENGTH);

		float fTime = results.FetchFloat(1);
		char sTime[16];
		FormatSeconds(fTime, sTime, 16);

		char sDisplay[128];
		FormatEx(sDisplay, 128, "%T: %s", "WRTime", client, sTime);
		hMenu.AddItem("-1", sDisplay, ITEMDRAW_DISABLED);

		int iStyle = results.FetchInt(3);
		int iJumps = results.FetchInt(2);
		float fPerfs = results.FetchFloat(9);

		if(Shavit_GetStyleSettingInt(iStyle, "autobhop"))
		{
			FormatEx(sDisplay, 128, "%T: %d", "WRJumps", client, iJumps);
		}
		else
		{
			FormatEx(sDisplay, 128, "%T: %d (%.2f%%)", "WRJumps", client, iJumps, fPerfs);
		}

		hMenu.AddItem("-1", sDisplay, ITEMDRAW_DISABLED);

		FormatEx(sDisplay, 128, "%T: %d", "WRCompletions", client, results.FetchInt(13));
		hMenu.AddItem("-1", sDisplay, ITEMDRAW_DISABLED);

		FormatEx(sDisplay, 128, "%T: %s", "WRStyle", client, gS_StyleStrings[iStyle].sStyleName);
		hMenu.AddItem("-1", sDisplay, ITEMDRAW_DISABLED);

		results.FetchString(6, sMap, sizeof(sMap));

		float fPoints = results.FetchFloat(10);

		if(gB_Rankings && fPoints > 0.0)
		{
			FormatEx(sDisplay, 128, "%T: %.03f", "WRPointsCap", client, fPoints);
			hMenu.AddItem("-1", sDisplay, ITEMDRAW_DISABLED);
		}

		iSteamID = results.FetchInt(4);

		char sDate[32];
		results.FetchString(5, sDate, 32);

		if(sDate[4] != '-')
		{
			FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", StringToInt(sDate));
		}

		FormatEx(sDisplay, 128, "%T: %s", "WRDate", client, sDate);
		hMenu.AddItem("-1", sDisplay, ITEMDRAW_DISABLED);

		int strafes = results.FetchInt(7);
		float sync = results.FetchFloat(8);

		if(iJumps > 0 || strafes > 0)
		{
			FormatEx(sDisplay, 128, (sync != -1.0)? "%T: %d (%.02f%%)":"%T: %d", "WRStrafes", client, strafes, sync);
			hMenu.AddItem("-1", sDisplay, ITEMDRAW_DISABLED);
		}

		char sMenuItem[64];
		char sInfo[32];

		if(stage == 0)
		{
			FormatEx(sMenuItem, 64, "%T", "CheckpointRecord", client);
			FormatEx(sInfo, 32, "3;%d", id);
			hMenu.AddItem(sInfo, sMenuItem);
		}

		if(gB_Stats)
		{
			FormatEx(sMenuItem, 64, "%T", "WRPlayerStats", client);
			FormatEx(sInfo, 32, "0;%d", iSteamID);
			hMenu.AddItem(sInfo, sMenuItem);
		}

		FormatEx(sMenuItem, 64, "%T", "OpenSteamProfile", client);
		FormatEx(sInfo, 32, "2;%d", iSteamID);
		hMenu.AddItem(sInfo, sMenuItem);

		if(CheckCommandAccess(client, "sm_delete", ADMFLAG_RCON))
		{
			FormatEx(sMenuItem, 64, "%T", "WRDeleteRecord", client);
			FormatEx(sInfo, 32, "1;%d", id);
			hMenu.AddItem(sInfo, sMenuItem);
		}

		if (stage == 0)
		{
			GetTrackName(client, results.FetchInt(11), sTrack, 32);
		}
		else
		{
			FormatEx(sTrack, sizeof(sTrack), "%T %d", "WRStage", client, stage);
		}

		Shavit_PrintSteamIDOnce(client, iSteamID, sName);
	}
	else
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "DatabaseError", client);
		hMenu.AddItem("-1", sMenuItem);
	}

	if(strlen(sName) > 0)
	{
		FormatEx(sFormattedTitle, 256, "%s [U:1:%u]\n--- %s: [%s]", sName, iSteamID, sMap, sTrack);
	}
	else
	{
		FormatEx(sFormattedTitle, 256, "%T", "Error", client);
	}

	hMenu.SetTitle(sFormattedTitle);
	hMenu.ExitBackButton = true;
	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int SubMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, 32);

		if(gB_Stats && StringToInt(sInfo) != -1)
		{
			char sExploded[2][32];
			ExplodeString(sInfo, ";", sExploded, 2, 32, true);

			int first = StringToInt(sExploded[0]);

			switch(first)
			{
				case 0:
				{
					FakeClientCommand(param1, "sm_profile [U:1:%s]", sExploded[1]);
				}
				case 1:
				{
					OpenDeleteMenu(param1, StringToInt(sExploded[1]));
				}
				case 2:
				{
					char url[192+1];
					FormatEx(url, sizeof(url), "https://steamcommunity.com/profiles/[U:1:%s]", sExploded[1]);
					ShowMOTDPanel(param1, "you just lost The Game", url, MOTDPANEL_TYPE_URL);
				}
				case 3:
				{
					OpenCheckpointRecordsMenu(param1, StringToInt(sExploded[1]));
				}
			}
		}
		else
		{
			StartWRMenu(param1);
		}
	}
	else if(action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack)
		{
			if (gH_PBMenu[param1])
			{
				gH_PBMenu[param1].DisplayAt(param1, gI_PBMenuPos[param1], MENU_TIME_FOREVER);
			}
			else
			{
				StartWRMenu(param1);
			}
		}
		else
		{
			delete gH_PBMenu[param1];
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OpenCheckpointRecordsMenu(int client, int id)
{
	char sQuery[512];
	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(id);

	FormatEx(sQuery, sizeof(sQuery), 
		"SELECT a.time, a.checkpoint FROM %scptimes a JOIN %splayertimes b ON a.map = b.map AND a.track = b.track AND a.style = b.style AND a.auth = b.auth AND b.id = %d;",
		gS_MySQLPrefix, gS_MySQLPrefix, id);
	QueryLog(gH_SQL, SQL_CheckpointRecordsMenu_Callback, sQuery, pack, DBPrio_High);
}

public void SQL_CheckpointRecordsMenu_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int client = GetClientFromSerial(data.ReadCell());
	int id = data.ReadCell();
	delete data;

	if(results == null)
	{
		LogError("Timer (WR CheckpointRecordsMenu) SQL query failed. Reason: %s", error);

		return;
	}

	float fTime;
	int num;
	char sTime[32];
	char sMenuItem[64];
	char sInfo[4];

	Menu menu = new Menu(MenuHandler_CheckpointRecords);
	menu.SetTitle("Checkpoint records.\n ");

	FormatEx(sInfo, sizeof(sInfo), "%d", id);
	
	while(results.FetchRow())
	{
		fTime = results.FetchFloat(0);
		num = results.FetchInt(1);
		FormatSeconds(fTime, sTime, sizeof(sTime));
		FormatEx(sMenuItem, sizeof(sMenuItem), "CP %02d | Time: %s", num, sTime);
		menu.AddItem(sInfo, sMenuItem, ITEMDRAW_DISABLED);
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem(sInfo, "No checkpoint records.", ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_CheckpointRecords(Menu menu, MenuAction action, int param1, int param2)
{
	char sInfo[32];
	menu.GetItem(0, sInfo, 32);

	if (action == MenuAction_Select)
    {
		//nothing here
	}
	else if(action == MenuAction_Cancel)
	{
		if (param2 == MenuCancel_ExitBack)
		{
			OpenSubMenu(param1, StringToInt(sInfo), 0);
		}
		else
		{
			delete gH_PBMenu[param1];
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void Shavit_OnDatabaseLoaded()
{
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = Shavit_GetDatabase(gI_Driver);

	gB_Connected = true;
	OnMapStart();
}


public void Shavit_OnFinishStage(int client, int track, int style, int stage, float time, float oldtime, int jumps, int strafes, float sync, float perfs, float avgvel, float maxvel, float startvel, float endvel, int timestamp)
{
	if (!gB_LoadedStageCache[client] || !gB_LoadedCache[client])
	{
		return;
	}

	int iOverwrite = 0;
	bool bIncrementCompletions = true;

	int iSteamID = GetSteamAccountID(client);

	if(Shavit_GetStyleSettingInt(style, "unranked") || Shavit_IsPracticeMode(client))
	{
		iOverwrite = 0;
		bIncrementCompletions = false;
	}
	else if(gF_PlayerStageRecord[client][style][stage] == 0.0)
	{
		iOverwrite = 1;
	}
	else if(time < gF_PlayerStageRecord[client][style][stage])
	{
		iOverwrite = 2;
	}

	bool bEveryone = (iOverwrite > 0);
	bool bServerFirstCompletion = (gF_StageWRTime[style][stage] == 0.0);
	float fDifferenceWR = (time - gF_StageWRTime[style][stage]);
	char sMessage[255];
	char sMessage2[255];

	char sName[32+1];
	GetClientName(client, sName, sizeof(sName));

	if(iOverwrite > 0 && (time < gF_StageWRTime[style][stage] || bServerFirstCompletion))	//new stage wr
	{
		float fOldWR = gF_StageWRTime[style][stage];
		gF_StageWRTime[style][stage] = time;
		gF_StageWRStartVelocity[style][stage] = startvel;
		gF_StageWREndVelocity[style][stage] = endvel;

		gI_StageWRSteamID[style][stage] = iSteamID;

		char sSteamID[20];
		IntToString(iSteamID, sSteamID, sizeof(sSteamID));

		ReplaceString(sName, sizeof(sName), "#", "?");
		gSM_StageWRNames.SetString(sSteamID, sName, true);

		Call_StartForward(gH_OnWorldRecord);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_PushCell(strafes);
		Call_PushCell(sync);
		Call_PushCell(track);
		Call_PushCell(stage);
		Call_PushCell(fOldWR);
		Call_PushCell(oldtime);
		Call_PushCell(perfs);
		Call_PushCell(avgvel);
		Call_PushCell(maxvel);
		Call_PushCell(timestamp);
		Call_Finish();
	}

	char sTime[32];
	FormatSeconds(time, sTime, 32);

	char sStage[16];
	Format(sStage, 16, "%T %d", "WRStage", bEveryone ? LANG_SERVER:client, stage);

	char sDifferenceWR[32];
	FormatSeconds(fDifferenceWR, sDifferenceWR, 32, true);

	if(fDifferenceWR < 0.0)
	{
		Format(sDifferenceWR, sizeof(sDifferenceWR), "%s%s%s", gS_ChatStrings.sImproving, sDifferenceWR, gS_ChatStrings.sText);
	}
	else
	{
		Format(sDifferenceWR, sizeof(sDifferenceWR), "%s+%s%s", gS_ChatStrings.sWarning, sDifferenceWR, gS_ChatStrings.sText);
	}

	float fDifferencePB = (time - gF_PlayerStageRecord[client][style][stage]);
	char sDifferencePB[32];
	FormatSeconds(fDifferencePB, sDifferencePB, 32, true);

	if(fDifferencePB < 0.0)
	{
		Format(sDifferencePB, sizeof(sDifferencePB), "%s%s%s", gS_ChatStrings.sImproving, sDifferencePB, gS_ChatStrings.sText);
	}
	else
	{
		Format(sDifferencePB, sizeof(sDifferencePB), "%s+%s%s", gS_ChatStrings.sWarning, sDifferencePB, gS_ChatStrings.sText);
	}

	int iRank = GetStageRankForTime(style, time, stage);
	int iRankCount = GetStageRecordAmount(style, stage);

	if(iOverwrite > 0)  //Valid Run
	{
		float fPoints = gB_Rankings ? Shavit_GuessPointsForTime(track, stage, style, iRank, -1) : 0.0;
		float fGainedPoints = 0.0;

		char sQuery[1024];

		if(iOverwrite == 1) //Player first finished in server
		{
			if(bServerFirstCompletion)	//First Compeletion in server
			{
				FormatEx(sMessage, 255, "%T", 
					"ServerFirstCompletion", LANG_SERVER,
					gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText, 
					gS_ChatStrings.sVariable, sStage, gS_ChatStrings.sText, 
					gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, 
					gS_ChatStrings.sVariable, 1, gS_ChatStrings.sText, 
					gS_ChatStrings.sVariable, 1, gS_ChatStrings.sText, 
					gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
			}
			else
			{
				FormatEx(sMessage, 255, "%T", 
					"PlayerFirstCompletion", LANG_SERVER,
					gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText, 
					gS_ChatStrings.sVariable, sStage, gS_ChatStrings.sText, 
					gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, 
					sDifferenceWR, 
					gS_ChatStrings.sVariable, iRank, gS_ChatStrings.sText, 
					gS_ChatStrings.sVariable, iRankCount+1, gS_ChatStrings.sText, 
					gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
			}

			fGainedPoints = gB_Rankings ? fPoints : 0.0;

			FormatEx(sMessage2, sizeof(sMessage2), "%T", "CompletionPointsInfo", client,
				gS_ChatStrings.sVariable2, fGainedPoints, gS_ChatStrings.sText,
				gS_ChatStrings.sVariable, sStage, gS_ChatStrings.sText,
				gS_ChatStrings.sVariable, iRank, gS_ChatStrings.sText);

			FormatEx(sQuery, sizeof(sQuery),
				"INSERT INTO %sstagetimes (auth, map, time, jumps, date, style, strafes, sync, points, track, stage, perfs, startvel, endvel) VALUES (%d, '%s', %.9f, %d, %d, %d, %d, %.2f, %f, %d, %d, %.2f, %f, %f);",
				gS_MySQLPrefix, iSteamID, gS_Map, time, jumps, timestamp, style, strafes, sync, fPoints, track, stage, perfs, startvel, endvel);
		}
		else // Better than PB, Maybe Beat the wr
		{
			FormatEx(sMessage, 255, "%T", 
				"NotFirstCompletion", LANG_SERVER,
				gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText, 
				gS_ChatStrings.sVariable, sStage, gS_ChatStrings.sText, 
				gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, 
				sDifferenceWR, sDifferencePB,
				gS_ChatStrings.sVariable, iRank, gS_ChatStrings.sText, 
				gS_ChatStrings.sVariable, iRankCount, gS_ChatStrings.sText, 
				gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);

			int oldRank = GetStageRankForTime(style, oldtime, stage);
			fGainedPoints = gB_Rankings ? fPoints - Shavit_GuessPointsForTime(track, stage, style, oldRank, -1) : 0.0;

			if(fGainedPoints > 0.0)
			{
				FormatEx(sMessage2, sizeof(sMessage2), "%T", "ImprovingPointsInfo", client,
					gS_ChatStrings.sVariable2, fGainedPoints, gS_ChatStrings.sText,
					gS_ChatStrings.sVariable, oldRank, gS_ChatStrings.sText,
					gS_ChatStrings.sVariable, iRank, gS_ChatStrings.sText,
					gS_ChatStrings.sVariable, sStage, gS_ChatStrings.sText);
			}

			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %sstagetimes SET time = %.9f, jumps = %d, date = %d, strafes = %d, sync = %.02f, points = %f, perfs = %.2f, completions = completions + 1, startvel = %f, endvel = %f WHERE map = '%s' AND auth = %d AND style = %d AND track = %d AND stage = %d;",
				gS_MySQLPrefix, time, jumps, timestamp, strafes, sync, fPoints, perfs, startvel, endvel, gS_Map, iSteamID, style, track, stage);
		}

		QueryLog(gH_SQL, SQL_OnFinishStage_Callback, sQuery, GetClientSerial(client), DBPrio_High);
		
		Call_StartForward(gH_OnFinishStage_Post);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_PushCell(strafes);
		Call_PushCell(sync);
		Call_PushCell(iRank);
		Call_PushCell(iOverwrite);
		Call_PushCell(stage);
		Call_PushCell(oldtime);
		Call_PushCell(perfs);
		Call_PushCell(avgvel);
		Call_PushCell(maxvel);
		Call_PushCell(timestamp);
		Call_Finish();
	}

	if(bIncrementCompletions)
	{
		if (iOverwrite == 0)
		{
			char sQuery[512];
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %sstagetimes SET completions = completions + 1 WHERE map = '%s' AND auth = %d AND style = %d AND track = %d AND stage = %d;",
				gS_MySQLPrefix, gS_Map, iSteamID, style, track, stage);

			QueryLog(gH_SQL, SQL_OnIncrementCompletions_Callback, sQuery, 0, DBPrio_Low);
		}

		gI_PlayerStageCompletion[client][style][track]++;

		if(iOverwrite == 0 && !Shavit_GetStyleSettingInt(style, "unranked"))
		{
			FormatEx(sMessage, 255, "%T",
				"WorseTime", client,
				gS_ChatStrings.sVariable, sStage, gS_ChatStrings.sText, 
				gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, 
				sDifferenceWR, sDifferencePB,
				gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
		}
	}
	else
	{
		FormatEx(sMessage, 255, "%T",
			"UnrankedTime", client, 
			gS_ChatStrings.sVariable, sStage, gS_ChatStrings.sText, 
			gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, 
			gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
	}

	Action aResult = Plugin_Continue;

	if(aResult < Plugin_Handled)
	{
		if(bEveryone)
		{
			for(int i = 1; i <= MaxClients; i++)
			{
				if(IsValidClient(i))	//Print to spectator if target finished and worse
				{
					if(i == client)
					{
						if((Shavit_GetMessageSetting(i) & MSG_FINISHSTAGE) == 0)
						{
							Shavit_PrintToChat(i, "%s", sMessage);								
						}
					}
					else if((Shavit_GetMessageSetting(i) & MSG_OTHER) == 0)
					{
						Shavit_PrintToChat(i, "%s", sMessage);						
					}
				}
			}
		}
		else
		{
			if((Shavit_GetMessageSetting(client) & MSG_FINISHSTAGE) == 0)
			{
				Shavit_PrintToChat(client, "%s", sMessage);				
			}

			for(int i = 1; i <= MaxClients; i++)
			{
				if(client != i && IsValidClient(i) && GetSpectatorTarget(i) == client && (Shavit_GetMessageSetting(i) & MSG_OTHER) == 0)	
				{	//Print to spectator if target finished and worse
					if(bIncrementCompletions && !Shavit_GetStyleSettingInt(style, "unranked"))
					{
						FormatEx(sMessage, 255, "%T", "NotFirstCompletionWorse", i, 
							gS_ChatStrings.sVariable2, sName, gS_ChatStrings.sText, 
							gS_ChatStrings.sVariable, sStage, gS_ChatStrings.sText, 
							gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, 
							sDifferenceWR, sDifferencePB,
							gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);						
					}
					else
					{
						FormatEx(sMessage, 255, "%T", "UnrankedTime", client, 
							gS_ChatStrings.sVariable, sStage, gS_ChatStrings.sText, 
							gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, 
							gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
					}
					
					Shavit_PrintToChat(i, "%s", sMessage);
				}
			}
		}

		if ((Shavit_GetMessageSetting(client) & MSG_EXTRAFINISHINFO) == 0)
		{
			Shavit_PrintToChat(client, "%T", "ExtraFinishInfo", client, sStage, 
			gS_ChatStrings.sVariable, avgvel, gS_ChatStrings.sText, 
			gS_ChatStrings.sVariable, maxvel, gS_ChatStrings.sText, 
			gS_ChatStrings.sVariable, startvel, gS_ChatStrings.sText, 
			gS_ChatStrings.sVariable, endvel, gS_ChatStrings.sText, 
			gS_ChatStrings.sVariable, sync, gS_ChatStrings.sText);
		}		
		
		if (sMessage2[0] != 0 && (Shavit_GetMessageSetting(client) & MSG_POINTINFO) == 0)
		{
			Shavit_PrintToChat(client, "%s", sMessage2);
		}
	}

	// update pb cache only after sending the message so we can grab the old one inside the Shavit_OnFinishMessage forward
	if(iOverwrite > 0)
	{
		gF_PlayerStageRecord[client][style][stage] = time;
		gF_PlayerStageStartVelocity[client][style][stage] = startvel;
		gF_PlayerStageEndVelocity[client][style][stage] = endvel;

	}
}


public Action Shavit_OnFinishStagePre(int client, timer_snapshot_t snapshot)
{
	if (!snapshot.bStageTimeValid)
	{
		if(Shavit_IsOnlyStageMode(client))
		{
			Shavit_StopTimer(client, false);
		}

		return Plugin_Stop;
	}

	return Plugin_Continue;
}


public void SQL_OnFinishStage_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR OnFinishStage) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	UpdateWRCache(client);
}


public void Shavit_OnFinish(int client, int style, float time, int jumps, int strafes, float sync, int track, float oldtime, float perfs, float avgvel, float maxvel, float startvel, float endvel, int timestamp)
{
	// do not risk overwriting the player's data if their PB isn't loaded to cache yet
	if (!gB_LoadedStageCache[client] || !gB_LoadedCache[client])
	{
		return;
	}

#if 0
	time = view_as<float>(0x43611FB3); // 225.123825; // this value loses accuracy and becomes 0x43611FBE \ 225.123992 once it's returned from mysql
	PrintToServer("time = %f %X record = %f %X", time, time, gF_WRTime[style][track], gF_WRTime[style][track]);
#endif

	int iSteamID = GetSteamAccountID(client);

	char sTime[32];
	FormatSeconds(time, sTime, 32);

	// 0 - no query
	// 1 - insert
	// 2 - update
	bool bIncrementCompletions = true;
	int iOverwrite = 0;

	if(Shavit_GetStyleSettingInt(style, "unranked") || Shavit_IsPracticeMode(client))
	{
		iOverwrite = 0; // ugly way of not writing to database
		bIncrementCompletions = false;
	}
	else if(gF_PlayerRecord[client][style][track] == 0.0)
	{
		iOverwrite = 1;
	}
	else if(time < gF_PlayerRecord[client][style][track])
	{
		iOverwrite = 2;
	}

	bool bEveryone = (iOverwrite > 0);
	bool bServerFirstCompletion = (gF_WRTime[style][track] == 0.0);
	float fDifferenceWR = (time - gF_WRTime[style][track]);
	char sMessage[255];
	char sMessage2[255];
	float cptimes[MAX_STAGES];

	char sTrack[32];
	GetTrackName(bEveryone ? LANG_SERVER:client, track, sTrack, 32);

	if (iOverwrite > 0)
	{
		Shavit_GetClientCPTimes(client, cptimes);		
	}

	char sName[32+1];
	GetClientName(client, sName, sizeof(sName));

	if(iOverwrite > 0 && (time < gF_WRTime[style][track] || bServerFirstCompletion)) // WR?
	{
		float fOldWR = gF_WRTime[style][track];
		gF_WRTime[style][track] = time;
		gF_WRStartVelocity[style][track] = startvel;
		gF_WREndVelocity[style][track] = endvel;

		gI_WRSteamID[style][track] = iSteamID;

		char sSteamID[20];
		IntToString(iSteamID, sSteamID, sizeof(sSteamID));

		ReplaceString(sName, sizeof(sName), "#", "?");
		gSM_WRNames.SetString(sSteamID, sName, true);

		Call_StartForward(gH_OnWorldRecord);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_PushCell(strafes);
		Call_PushCell(sync);
		Call_PushCell(track);
		Call_PushCell(0);
		Call_PushCell(fOldWR);
		Call_PushCell(oldtime);
		Call_PushCell(perfs);
		Call_PushCell(avgvel);
		Call_PushCell(maxvel);
		Call_PushCell(timestamp);
		Call_Finish();

		#if defined DEBUG
		Shavit_PrintToChat(client, "old: %.01f new: %.01f", fOldWR, time);
		#endif

		ReplaceCPTimes(gH_SQL, client, style, track, cptimes, true);
	}

	int iRank = GetRankForTime(style, time, track);
	int iRankCount = GetRecordAmount(style, track);

	if(iRank >= iRankCount)
	{
		Call_StartForward(gH_OnWorstRecord);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_PushCell(strafes);
		Call_PushCell(sync);
		Call_PushCell(track);
		Call_PushCell(oldtime);
		Call_PushCell(perfs);
		Call_PushCell(avgvel);
		Call_PushCell(maxvel);
		Call_PushCell(timestamp);
		Call_Finish();
	}
	
	char sDifferenceWR[32];
	FormatSeconds(fDifferenceWR, sDifferenceWR, 32, true);

	if(fDifferenceWR < 0.0)
	{
		Format(sDifferenceWR, sizeof(sDifferenceWR), "%s%s%s", gS_ChatStrings.sImproving, sDifferenceWR, gS_ChatStrings.sText);
	}
	else
	{
		Format(sDifferenceWR, sizeof(sDifferenceWR), "%s+%s%s", gS_ChatStrings.sWarning, sDifferenceWR, gS_ChatStrings.sText);
	}

	float fDifferencePB = (time - gF_PlayerRecord[client][style][track]);
	char sDifferencePB[32];
	FormatSeconds(fDifferencePB, sDifferencePB, 32, true);

	if(fDifferencePB < 0.0)
	{
		Format(sDifferencePB, sizeof(sDifferencePB), "%s%s%s", gS_ChatStrings.sImproving, sDifferencePB, gS_ChatStrings.sText);
	}
	else
	{
		Format(sDifferencePB, sizeof(sDifferencePB), "%s+%s%s", gS_ChatStrings.sWarning, sDifferencePB, gS_ChatStrings.sText);
	}

	if(iOverwrite > 0)  //Valid Run
	{
		float fPoints = gB_Rankings ? Shavit_GuessPointsForTime(track, 0, style, iRank, -1) : 0.0;
		float fGainedPoints = 0.0;

		char sQuery[1024];

		if(iOverwrite == 1) //Player first finished in server
		{
			if(bServerFirstCompletion)	//First Compeletion in server
			{
				FormatEx(sMessage, 255, "%T",
					"ServerFirstCompletion", LANG_SERVER, 
					gS_ChatStrings.sVariable2, sName, 
					gS_ChatStrings.sText, gS_ChatStrings.sVariable, sTrack, 
					gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, 
					gS_ChatStrings.sText, gS_ChatStrings.sVariable, iRank,
					gS_ChatStrings.sText, gS_ChatStrings.sVariable, 1,
					gS_ChatStrings.sText, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
			}
			else
			{
				FormatEx(sMessage, 255, "%T",
					"PlayerFirstCompletion", LANG_SERVER, 
					gS_ChatStrings.sVariable2, sName, 
					gS_ChatStrings.sText, gS_ChatStrings.sVariable, sTrack, 
					gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, 
					gS_ChatStrings.sText, sDifferenceWR,
					gS_ChatStrings.sVariable, iRank,
					gS_ChatStrings.sText, gS_ChatStrings.sVariable, iRankCount + 1,
					gS_ChatStrings.sText, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
			}

			fGainedPoints = gB_Rankings ? fPoints : 0.0;

			FormatEx(sMessage2, sizeof(sMessage2), "%T", "CompletionPointsInfo", client,
				gS_ChatStrings.sVariable2, fGainedPoints, gS_ChatStrings.sText,
				gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText,
				gS_ChatStrings.sVariable, iRank, gS_ChatStrings.sText);			

			FormatEx(sQuery, sizeof(sQuery),
				"INSERT INTO %splayertimes (auth, map, time, jumps, date, style, strafes, sync, points, track, perfs, startvel, endvel) VALUES (%d, '%s', %.9f, %d, %d, %d, %d, %.2f, %f, %d, %.2f, %f, %f);",
				gS_MySQLPrefix, iSteamID, gS_Map, time, jumps, timestamp, style, strafes, sync, fPoints, track, perfs, startvel, endvel);
		}
		else // Better than PB, Maybe Beat the wr
		{
			FormatEx(sMessage, 255, "%T",
				"NotFirstCompletion", LANG_SERVER, 
				gS_ChatStrings.sVariable2, sName, 
				gS_ChatStrings.sText, gS_ChatStrings.sVariable, sTrack, 
				gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, 
				gS_ChatStrings.sText, sDifferenceWR, sDifferencePB,
				gS_ChatStrings.sVariable, iRank,
				gS_ChatStrings.sText, gS_ChatStrings.sVariable, iRankCount,
				gS_ChatStrings.sText, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);

			int oldRank = GetRankForTime(style, oldtime, track);
			fGainedPoints = gB_Rankings ? fPoints - Shavit_GuessPointsForTime(track, 0, style, oldRank, -1) : 0.0;

			if(fGainedPoints > 0.0)
			{
				FormatEx(sMessage2, sizeof(sMessage2), "%T", "ImprovingPointsInfo", client,
					gS_ChatStrings.sVariable2, fGainedPoints, gS_ChatStrings.sText,
					gS_ChatStrings.sVariable, oldRank, gS_ChatStrings.sText,
					gS_ChatStrings.sVariable, iRank, gS_ChatStrings.sText,
					gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);				
			}

			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %splayertimes SET time = %.9f, jumps = %d, date = %d, strafes = %d, sync = %.02f, points = %f, perfs = %.2f, completions = completions + 1, startvel = %f, endvel = %f WHERE map = '%s' AND auth = %d AND style = %d AND track = %d;",
				gS_MySQLPrefix, time, jumps, timestamp, strafes, sync, fPoints, perfs, startvel, endvel, gS_Map, iSteamID, style, track);
		}

		ReplaceCPTimes(gH_SQL, client, style, track, cptimes, false);

		QueryLog(gH_SQL, SQL_OnFinish_Callback, sQuery, GetClientSerial(client), DBPrio_High);

		Call_StartForward(gH_OnFinish_Post);
		Call_PushCell(client);
		Call_PushCell(style);
		Call_PushCell(time);
		Call_PushCell(jumps);
		Call_PushCell(strafes);
		Call_PushCell(sync);
		Call_PushCell(iRank);
		Call_PushCell(iOverwrite);
		Call_PushCell(track);
		Call_PushCell(oldtime);
		Call_PushCell(perfs);
		Call_PushCell(avgvel);
		Call_PushCell(maxvel);
		Call_PushCell(timestamp);
		Call_Finish();
	}

	if(bIncrementCompletions)
	{
		if (iOverwrite == 0)
		{
			char sQuery[512];
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %splayertimes SET completions = completions + 1 WHERE map = '%s' AND auth = %d AND style = %d AND track = %d;",
				gS_MySQLPrefix, gS_Map, iSteamID, style, track);

			QueryLog(gH_SQL, SQL_OnIncrementCompletions_Callback, sQuery, 0, DBPrio_Low);
		}

		gI_PlayerCompletion[client][style][track]++;

		if(iOverwrite == 0 && !Shavit_GetStyleSettingInt(style, "unranked"))
		{
			FormatEx(sMessage, 255, "%T",
				"WorseTime", client, 
				gS_ChatStrings.sVariable, sTrack, 
				gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, 
				gS_ChatStrings.sText, sDifferenceWR, sDifferencePB,
				gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
		}
	}
	else
	{
		FormatEx(sMessage, 255, "%T",
			"UnrankedTime", client, 
			gS_ChatStrings.sVariable, sTrack, 
			gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, 
			gS_ChatStrings.sText, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
	}

	timer_snapshot_t aSnapshot;
	Shavit_SaveSnapshot(client, aSnapshot);

	Action aResult = Plugin_Continue;
	Call_StartForward(gH_OnFinishMessage);
	Call_PushCell(client);
	Call_PushCellRef(bEveryone);
	Call_PushArrayEx(aSnapshot, sizeof(timer_snapshot_t), SM_PARAM_COPYBACK);
	Call_PushCell(iOverwrite);
	Call_PushCell(iRank);
	Call_PushStringEx(sMessage, 255, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(255);
	Call_PushStringEx(sMessage2, sizeof(sMessage2), SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(sizeof(sMessage2));
	Call_Finish(aResult);

	if(aResult < Plugin_Handled)
	{
		if(bEveryone)
		{
			for(int i = 1; i <= MaxClients; i++)
			{
				if(i == client)
				{
					if((Shavit_GetMessageSetting(i) & MSG_FINISHMAP) == 0)
					{
						Shavit_PrintToChat(i, "%s", sMessage);									
					}
				}
				else if((Shavit_GetMessageSetting(i) & MSG_OTHER) == 0)
				{
					Shavit_PrintToChat(i, "%s", sMessage);		
				}
			}
		}
		else
		{
			if((Shavit_GetMessageSetting(client) & MSG_FINISHMAP) == 0)
			{
				Shavit_PrintToChat(client, "%s", sMessage);
			}

			for(int i = 1; i <= MaxClients; i++)
			{
				if(client != i && IsValidClient(i) && GetSpectatorTarget(i) == client && (Shavit_GetMessageSetting(i) & MSG_OTHER) == 0)	//Print to spectator if target finished and worse
				{
					if(bIncrementCompletions && !Shavit_GetStyleSettingInt(style, "unranked"))
					{
						FormatEx(sMessage, sizeof(sMessage), "%T", "NotFirstCompletionWorse", i, 
							gS_ChatStrings.sVariable2, sName, 
							gS_ChatStrings.sText, gS_ChatStrings.sVariable, sTrack, 
							gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, 
							gS_ChatStrings.sText, sDifferenceWR, sDifferencePB,
							gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);						
					}
					else
					{
						FormatEx(sMessage, 255, "%T", "UnrankedTime", client, 
							gS_ChatStrings.sVariable, sTrack, 
							gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTime, 
							gS_ChatStrings.sText, gS_ChatStrings.sStyle, gS_StyleStrings[style].sStyleName, gS_ChatStrings.sText);
					}
					
					Shavit_PrintToChat(i, "%s", sMessage);
				}
			}
		}

		if ((Shavit_GetMessageSetting(client) & MSG_EXTRAFINISHINFO) == 0)
		{
			Shavit_PrintToChat(client, "%T", "ExtraFinishInfo", client, sTrack,	
			gS_ChatStrings.sVariable, avgvel, gS_ChatStrings.sText, 
			gS_ChatStrings.sVariable, maxvel, gS_ChatStrings.sText, 
			gS_ChatStrings.sVariable, startvel, gS_ChatStrings.sText, 
			gS_ChatStrings.sVariable, endvel, gS_ChatStrings.sText, 
			gS_ChatStrings.sVariable, sync, gS_ChatStrings.sText);
		}

		if (sMessage2[0] != 0 && ((Shavit_GetMessageSetting(client) & MSG_POINTINFO) == 0))
		{
			Shavit_PrintToChat(client, "%s", sMessage2);
		}
	}

	// update pb cache only after sending the message so we can grab the old one inside the Shavit_OnFinishMessage forward
	if(iOverwrite > 0)
	{
		gF_PlayerRecord[client][style][track] = time;
		gF_PlayerStartVelocity[client][style][track] = startvel;
		gF_PlayerEndVelocity[client][style][track] = endvel;
	}
}

public void SQL_OnIncrementCompletions_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR OnIncrementCompletions) SQL query failed. Reason: %s", error);

		return;
	}
}

public void SQL_OnFinish_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR OnFinish) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	UpdateWRCache(client);
}

public void ReplaceCPTimes(Database db, int client, int style, int track, float[] cptimes, bool wr)
{
	if (track != Track_Main)
	{
		return;
	}

	int steamid = GetSteamAccountID(client);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `%s%s` WHERE style = %d AND track = %d AND map = '%s'",
	gS_MySQLPrefix, wr ? "cpwrs" : "cptimes", style, track, gS_Map);

	if(!wr)
	{
		FormatEx(sQuery, sizeof(sQuery), "%s AND auth = %d; ", sQuery, steamid);
	}

	int iCheckpointCounts = Shavit_GetCheckpointCount(track);
	QueryLog(db, SQL_ReplaceCPTimesFirst_Callback, sQuery, 0, DBPrio_High);

	Transaction trans = new Transaction();
	for (int i = 0; i < MAX_STAGES; i++)
	{
		if (i > iCheckpointCounts + 1)
		{
			break;
		}
		
		if(wr)
		{
			gA_StageCP_WR[style][track][i] = cptimes[i];
		}		
		else
		{
			gA_StageCP_PB[client][style][track].Set(i, cptimes[i]);			
		}
		
		if (cptimes[i] <= 0.0)
		{
			continue;
		}

		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO `%s%s` (`style`, `track`, `map`, `auth`, `time`, `checkpoint`) VALUES (%d, %d, '%s', %d, %f, %d);",
			gS_MySQLPrefix, wr ? "cpwrs" : "cptimes", style, track, gS_Map, steamid, cptimes[i], i
		);

		AddQueryLog(trans, sQuery);
	}

	db.Execute(trans, Trans_ReplaceCPTimes_Success, Trans_ReplaceCPTimes_Error, 0, DBPrio_High);
}

public void SQL_ReplaceCPTimesFirst_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(!db || !results || error[0])
	{
		LogError("SQL_ReplaceCPTimesFirst_Callback - Query failed! (%s)", error);

		return;
	}

	return;
}

public void Trans_ReplaceCPTimes_Success(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	return;
}

public void Trans_ReplaceCPTimes_Error(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (ReplaceStageTimes) SQL query failed %d/%d. Reason: %s", failIndex, numQueries, error);
}

void UpdateLeaderboards()
{
	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "SELECT p.style, p.track, %s, 0, p.id, p.auth, p.startvel, p.endvel, u.name FROM %splayertimes p LEFT JOIN %susers u ON p.auth = u.auth WHERE p.map = '%s' ORDER BY p.time ASC, p.date ASC;", gI_Driver == Driver_mysql ? "REPLACE(FORMAT(time, 9), ',', '')" : "printf(\"%.9f\", p.time)", gS_MySQLPrefix, gS_MySQLPrefix, gS_Map);
	QueryLog(gH_SQL, SQL_UpdateLeaderboards_Callback, sQuery);
}

public void SQL_UpdateLeaderboards_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR UpdateLeaderboards) SQL query failed. Reason: %s", error);

		return;
	}

	ResetLeaderboards();
	ResetWRs();

	while(results.FetchRow())
	{
		int style = results.FetchInt(0);
		int track = results.FetchInt(1);

		if(style >= gI_Styles || Shavit_GetStyleSettingInt(style, "unranked") || track >= TRACKS_SIZE)
		{
			continue;
		}

		float time = results.FetchFloat(2);


		if (gA_Leaderboard[style][track].Push(time) == 0) // pushed WR
		{
			gF_WRTime[style][track] = time;
			gI_WRRecordID[style][track] = results.FetchInt(4);
			gI_WRSteamID[style][track] = results.FetchInt(5);

			gF_WRStartVelocity[style][track] = results.FetchFloat(6);
			gF_WREndVelocity[style][track] = results.FetchFloat(7);

			char sSteamID[20];
			IntToString(gI_WRSteamID[style][track], sSteamID, sizeof(sSteamID));

			char sName[MAX_NAME_LENGTH];
			results.FetchString(8, sName, MAX_NAME_LENGTH);
			ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");
			gSM_WRNames.SetString(sSteamID, sName, false);
		}
	}

#if 0
	for(int i = 0; i < gI_Styles; i++)
	{
		if (Shavit_GetStyleSettingInt(i, "unranked"))
		{
			continue;
		}

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			SortADTArray(gA_Leaderboard[i][j], Sort_Ascending, Sort_Float);
		}
	}
#endif

	Call_StartForward(gH_OnWorldRecordsCached);
	Call_Finish();
}

void UpdateStageLeaderboards()
{
	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "SELECT p.style, p.stage, %s, 0, p.id, p.auth, p.startvel, p.endvel, u.name FROM %sstagetimes p LEFT JOIN %susers u ON p.auth = u.auth WHERE p.map = '%s' ORDER BY p.time ASC, p.date ASC;", gI_Driver == Driver_mysql ? "REPLACE(FORMAT(time, 9), ',', '')" : "printf(\"%.9f\", p.time)", gS_MySQLPrefix, gS_MySQLPrefix, gS_Map);
	QueryLog(gH_SQL, SQL_UpdateStageLeaderboards_Callback, sQuery);
}

public void SQL_UpdateStageLeaderboards_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (WR UpdateStageLeaderboards) SQL query failed. Reason: %s", error);

		return;
	}

	ResetStageLeaderboards();
	ResetStageWRs();

	while(results.FetchRow())
	{
		int style = results.FetchInt(0);
		int stage = results.FetchInt(1);

		if(style >= gI_Styles || Shavit_GetStyleSettingInt(style, "unranked") || stage > MAX_STAGES)
		{
			continue;
		}

		float time = results.FetchFloat(2);

		if (gA_StageLeaderboard[style][stage].Push(time) == 0)
		{
			gF_StageWRTime[style][stage] = time;
			gI_StageWRRecordID[style][stage] = results.FetchInt(4);
			gI_StageWRSteamID[style][stage] = results.FetchInt(5);

			char sSteamID[20];
			IntToString(gI_StageWRSteamID[style][stage], sSteamID, sizeof(sSteamID));

			gF_StageWRStartVelocity[style][stage] = results.FetchFloat(6);
			gF_StageWREndVelocity[style][stage] = results.FetchFloat(7);

			char sName[MAX_NAME_LENGTH];
			results.FetchString(8, sName, MAX_NAME_LENGTH);
			ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");
			gSM_StageWRNames.SetString(sSteamID, sName, false);
		}
	}

	Call_StartForward(gH_OnStageWorldRecordsCached);
	Call_Finish();
}

// public void Shavit_OnReachNextStage(int client, int track, int startStage, int endStage)
// {

// }

public void Shavit_OnReachNextCP(int client, int track, int checkpoint, float time)
{
	if(!Shavit_IsPracticeMode(client))
	{
		Shavit_SetClientCPTime(client, checkpoint, time);
	}

	int style = Shavit_GetBhopStyle(client);
	int iCheckpointCounts = Shavit_GetCheckpointCount(track);
	float fCPWR = gA_StageCP_WR[style][track][checkpoint];
	float fCPPB = Shavit_GetStageCPPB(client, track, style, checkpoint);

	char sTime[16];
	FormatSeconds(time, sTime, 16);

	if (fCPWR == 0.0) // no wr, early return
	{
		Shavit_PrintToChat(client, "%T", "CheckpointTime", client,
			gS_ChatStrings.sVariable2, checkpoint, gS_ChatStrings.sText, 
			gS_ChatStrings.sVariable2, iCheckpointCounts, gS_ChatStrings.sText,
			gS_ChatStrings.sVariable, sTime, gS_ChatStrings.sText);
		
		return;
	}

	float fDifferenceWR = (time - fCPWR);

	char sDifferenceWR[32];	//32 because of color
	FormatSeconds(fDifferenceWR, sDifferenceWR, 32);

	if(fDifferenceWR <= 0.0)
	{
		Format(sDifferenceWR, sizeof(sDifferenceWR), "%s%s%s", gS_ChatStrings.sImproving, sDifferenceWR, gS_ChatStrings.sText);
	}
	else
	{
		Format(sDifferenceWR, sizeof(sDifferenceWR), "%s+%s%s", gS_ChatStrings.sWarning, sDifferenceWR, gS_ChatStrings.sText);
	}

	if(fCPPB == 0.0)	// no pb
	{
		Shavit_PrintToChat(client, "%T", "WRCheckpointTime", client,
		gS_ChatStrings.sVariable2, checkpoint, gS_ChatStrings.sText, 
		gS_ChatStrings.sVariable2, iCheckpointCounts, gS_ChatStrings.sText,
		gS_ChatStrings.sVariable, sTime, gS_ChatStrings.sText, sDifferenceWR);
		
		return;
	}

	float fDifferencePB = (time - fCPPB);

	char sDifferencePB[32]; //32 because of color
	FormatSeconds(fDifferencePB, sDifferencePB, 32);

	if(fDifferencePB <= 0.0)
	{
		Format(sDifferencePB, sizeof(sDifferencePB), "%s%s%s", gS_ChatStrings.sImproving, sDifferencePB, gS_ChatStrings.sText);
	}
	else
	{
		Format(sDifferencePB, sizeof(sDifferencePB), "%s+%s%s", gS_ChatStrings.sWarning, sDifferencePB, gS_ChatStrings.sText);
	}

	if((Shavit_GetMessageSetting(client) & MSG_CHECKPOINT) == 0)
	{
		Shavit_PrintToChat(client, "%T", "WRPBCheckpointTime", client,
			gS_ChatStrings.sVariable2, checkpoint, gS_ChatStrings.sText, 
			gS_ChatStrings.sVariable2, iCheckpointCounts, gS_ChatStrings.sText,
			gS_ChatStrings.sVariable, sTime, gS_ChatStrings.sText, sDifferenceWR, sDifferencePB);		
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && GetSpectatorTarget(i) == client && (Shavit_GetMessageSetting(i) & MSG_CHECKPOINT) == 0)
		{
			Shavit_PrintToChat(client, "%T", "WRPBCheckpointTime", client,
				gS_ChatStrings.sVariable2, checkpoint, gS_ChatStrings.sText, 
				gS_ChatStrings.sVariable2, iCheckpointCounts, gS_ChatStrings.sText,
				gS_ChatStrings.sVariable, sTime, gS_ChatStrings.sText, sDifferenceWR, sDifferencePB);		
		}
	}
}

int GetRecordAmount(int style, int track)
{
	if(gA_Leaderboard[style][track] == null)
	{
		return 0;
	}

	return gA_Leaderboard[style][track].Length;
}

int GetRankForTime(int style, float time, int track)
{
	int iRecords = GetRecordAmount(style, track);

	if(time <= gF_WRTime[style][track] || iRecords <= 0)
	{
		return 1;
	}

	int i = 0;

	if (iRecords > 100)
	{
		int middle = iRecords/2;

		if (gA_Leaderboard[style][track].Get(middle) < time)
		{
			i = middle;
		}
		else
		{
			iRecords = middle;
		}
	}

	for (; i < iRecords; i++)
	{
		if (time <= gA_Leaderboard[style][track].Get(i))
		{
			return i+1;
		}
	}

	return (iRecords + 1);
}

int GetStageRankForTime(int style, float time, int stage)
{
	int iRecords = GetStageRecordAmount(style, stage);

	if(time <= gF_StageWRTime[style][stage] || iRecords <= 0)
	{
		return 1;
	}

	int i = 0;

	if (iRecords > 100)
	{
		int middle = iRecords/2;

		if (gA_StageLeaderboard[style][stage].Get(middle) < time)
		{
			i = middle;
		}
		else
		{
			iRecords = middle;
		}
	}

	for (; i < iRecords; i++)
	{
		if (time <= gA_StageLeaderboard[style][stage].Get(i))
		{
			return i+1;
		}
	}

	return (iRecords + 1);
}

int GetStageRecordAmount(int style, int stage)
{
	if(gA_StageLeaderboard[style][stage] == null)
	{
		return 0;
	}

	return gA_StageLeaderboard[style][stage].Length;
}