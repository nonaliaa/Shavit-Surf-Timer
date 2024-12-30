/*
 * shavit's Timer - Rankings
 * by: shavit, rtldg
 *
 * This file is part of shavit's Timer (https://github.com/shavitush/bhoptimer)
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

// Design idea:
// Rank 1 per map/style/track gets ((points per tier * tier) * 1.5) + (rank 1 time in seconds / 15.0) points.
// Records below rank 1 get points% relative to their time in comparison to rank 1.
//
// Bonus track gets a 0.25* final multiplier for points and is treated as tier 1.
//
// Points for all styles are combined to promote competitive and fair gameplay.
// A player that gets good times at all styles should be ranked high.
//
// Total player points are weighted in the following way: (descending sort of points)
// points[0] * 0.975^0 + points[1] * 0.975^1 + points[2] * 0.975^2 + ... + points[n] * 0.975^n
//
// The ranking leaderboard will be calculated upon: map start.
// Points are calculated per-player upon: connection/map.
// Points are calculated per-map upon: map start, map end, tier changes.
// Rankings leaderboard is re-calculated once per map change.
// A command will be supplied to recalculate all of the above.
//
// Heavily inspired by pp (performance points) from osu!, written by Tom94. https://github.com/ppy/osu-performance

#include <sourcemod>
#include <convar_class>
#include <dhooks>

#include <shavit/core>
#include <shavit/rankings>
#include <shavit/wr>
#include <shavit/zones>

#undef REQUIRE_PLUGIN

#undef REQUIRE_EXTENSIONS
#define USE_SHMAPTIERS 1
#if USE_SHMAPTIERS
#include <ripext>
#define SH_MAPINFO_URL "https://surfheaven.eu/api/mapinfo/"
#endif
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

// #define DEBUG

enum struct ranking_t
{
	int iRank;
	float fPoints;
	int iWRAmountAll;
	int iWRAmountCvar;
	int iWRHolderRankAll;
	int iWRHolderRankCvar;
	int iWRAmount[STYLE_LIMIT*2];
	int iWRHolderRank[STYLE_LIMIT*2];
}

char gS_MySQLPrefix[32];
Database gH_SQL = null;
bool gB_SQLWindowFunctions = false;
bool gB_SqliteHatesPOW = false;
int gI_Driver = Driver_unknown;

bool gB_Stats = false;
bool gB_Late = false;
bool gB_TierQueried = false;

int gI_Tier = 1; // No floating numbers for tiers, sorry.

char gS_Map[PLATFORM_MAX_PATH];
EngineVersion gEV_Type = Engine_Unknown;

ArrayList gA_ValidMaps = null;
StringMap gA_MapTiers = null;

// Convar gCV_PointsPerTier = null;
Convar gCV_BasicFinishPoints_Main = null;
Convar gCV_BasicFinishPoints_Bonus = null;
Convar gCV_BasicFinishPoints_Stage = null;
Convar gCV_MaxRankPoints_Main = null;
Convar gCV_MaxRankPoints_Bonus = null;
Convar gCV_MaxRankPoints_Stage = null;

Convar gCV_WeightingMultiplier = null;
Convar gCV_WeightingLimit = null;
Convar gCV_LastLoginRecalculate = null;
Convar gCV_MVPRankOnes_Slow = null;
Convar gCV_MVPRankOnes = null;
Convar gCV_MVPRankOnes_Main = null;
Convar gCV_DefaultTier = null;
Convar gCV_DefaultMaxVelocity = null;
Convar gCV_MinMaxVelocity = null;

ConVar sv_maxvelocity = null;

ranking_t gA_Rankings[MAXPLAYERS+1];

int gI_RankedPlayers = 0;
Menu gH_Top100Menu = null;

Handle gH_Forwards_OnTierAssigned = null;
Handle gH_Forwards_OnRankAssigned = null;

// Timer settings.
chatstrings_t gS_ChatStrings;
int gI_Styles = 0;
float gF_MaxVelocity;

bool gB_WorldRecordsCached = false;
bool gB_WRHolderTablesMade = false;
bool gB_WRHoldersRefreshed = false;
bool gB_WRHoldersRefreshedTimer = false;
int gI_WRHolders[2][STYLE_LIMIT];
int gI_WRHoldersAll;
int gI_WRHoldersCvar;

public Plugin myinfo =
{
	name = "[shavit-surf] Rankings",
	author = "shavit, rtldg",
	description = "A fair and competitive ranking system shavit surf timer. (This plugin is base on shavit's bhop timer)",
	version = SHAVIT_SURF_VERSION,
	url = "https://github.com/shavitush/bhoptimer"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("Shavit_GetMapTier", Native_GetMapTier);
	CreateNative("Shavit_GetMapTiers", Native_GetMapTiers);
	CreateNative("Shavit_GetPoints", Native_GetPoints);
	CreateNative("Shavit_GetRank", Native_GetRank);
	CreateNative("Shavit_GetRankedPlayers", Native_GetRankedPlayers);
	CreateNative("Shavit_Rankings_DeleteMap", Native_Rankings_DeleteMap);
	CreateNative("Shavit_GetWRCount", Native_GetWRCount);
	CreateNative("Shavit_GetWRHolders", Native_GetWRHolders);
	CreateNative("Shavit_GetWRHolderRank", Native_GetWRHolderRank);
	CreateNative("Shavit_GuessPointsForTime", Native_GuessPointsForTime);

	RegPluginLibrary("shavit-rankings");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	gEV_Type = GetEngineVersion();

	gH_Forwards_OnTierAssigned = CreateGlobalForward("Shavit_OnTierAssigned", ET_Event, Param_String, Param_Cell);
	gH_Forwards_OnRankAssigned = CreateGlobalForward("Shavit_OnRankAssigned", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	RegConsoleCmd("sm_tier", Command_Tier, "Prints the map's tier to chat.");
	RegConsoleCmd("sm_maptier", Command_Tier, "Prints the map's tier to chat. (sm_tier alias)");

	RegConsoleCmd("sm_rank", Command_Rank, "Show your or someone else's rank. Usage: sm_rank [name]");
	RegConsoleCmd("sm_top", Command_Top, "Show the top 100 players.");

	RegAdminCmd("sm_settier", Command_SetTier, ADMFLAG_RCON, "Change the map's tier. Usage: sm_settier <tier> [map]");
	RegAdminCmd("sm_setmaptier", Command_SetTier, ADMFLAG_RCON, "Change the map's tier. Usage: sm_setmaptier <tier> [map] (sm_settier alias)");

#if USE_SHMAPTIERS	
	RegAdminCmd("sm_useshtier", Command_UseSHTier, ADMFLAG_RCON, "Change the current map's tier to which Surf Heaven has assigned");
#endif

	RegAdminCmd("sm_setmaxvelocity", Command_SetMaxVelocity, ADMFLAG_RCON, "Change the map's sv_maxvelocity. Usage: sm_setmaxvelocity <value> [map]");
	RegAdminCmd("sm_setmaxvel", Command_SetMaxVelocity, ADMFLAG_RCON, "Change the map's sv_maxvelocity. Usage: sm_setmaxvel <value> [map] (sm_setmaxvelocity alias)");
	RegAdminCmd("sm_setmapmaxvelocity", Command_SetMaxVelocity, ADMFLAG_RCON, "Change the map's sv_maxvelocity. Usage: sm_setmapmaxvelocity <value> [map] (sm_setmaxvelocity alias)");
	RegAdminCmd("sm_setmapmaxvel", Command_SetMaxVelocity, ADMFLAG_RCON, "Change the map's sv_maxvelocity. Usage: sm_setmapmaxvelocity <value> [map] (sm_setmaxvelocity alias)");

	RegAdminCmd("sm_recalcmap", Command_RecalcMap, ADMFLAG_RCON, "Recalculate the current map's records' points.");

	// RegAdminCmd("sm_recalcall", Command_RecalcAll, ADMFLAG_ROOT, "Recalculate the points for every map on the server. Run this after you change the ranking multiplier for a style or after you install the plugin.");

	
	//its really a great design but someone may thought there are not enough point for beat a records, so i decide to rework it :( 
	//gCV_PointsPerTier = new Convar("shavit_rankings_pointspertier", "50.0", "Base points to use for per-tier scaling.\nRead the design idea to see how it works: https://github.com/shavitush/bhoptimer/issues/465", 0, true, 1.0);
	gCV_BasicFinishPoints_Main = new Convar("shavit_rankings_basicfinishpoint_main", "18.33", "Basic point for player when finished main.", 0, true, 0.0, false, 0.0);
	gCV_BasicFinishPoints_Bonus = new Convar("shavit_rankings_basicfinishpoint_bonus", "15.15", "Basic point for player when finished bonus.", 0, true, 0.0, false, 0.0);
	gCV_BasicFinishPoints_Stage = new Convar("shavit_rankings_basicfinishpoint_stage", "0.0", "Basic point for player when finished stage. (0.0 for using tier for basic point)", 0, true, 0.0, false, 0.0);
	
	gCV_MaxRankPoints_Main = new Convar("shavit_rankings_maxrankpoint_main", "833.3", "Max point for player's rank of main.", 0, true, 0.0, false, 0.0);
	gCV_MaxRankPoints_Bonus = new Convar("shavit_rankings_maxrankpoint_bonus", "494.4", "Max point for player's rank of bonus.", 0, true, 0.0, false, 0.0);
	gCV_MaxRankPoints_Stage = new Convar("shavit_rankings_maxrankpoint_stage", "288.8", "Max point for player's rank of stage.", 0, true, 0.0, false, 0.0);

	gCV_WeightingMultiplier = new Convar("shavit_rankings_weighting", "1.0", "Weighting multiplier. 1.0 to disable weighting.\nFormula: p[0] * this^0 + p[1] * this^1 + p[2] * this^2 + ... + p[n] * this^n\nRestart server to apply.", 0, true, 0.01, true, 1.0);
	gCV_WeightingLimit = new Convar("shavit_rankings_weighting_limit", "0", "Limit the number of times retrieved for calculating a player's weighted points to this number.\n0 = no limit\nFor reference, a weighting of 0.975 to the power of 300 is 0.00050278777 and results in pretty much nil points for any further weighted times.\nUnused when shavit_rankings_weighting is 1.0.\nYou probably won't need to change this unless you have hundreds of thousands of player times in your database.", 0, true, 0.0, false);
	gCV_LastLoginRecalculate = new Convar("shavit_rankings_llrecalc", "0", "Maximum amount of time (in minutes) since last login to recalculate points for a player.\nsm_recalcall does not respect this setting.\n0 - disabled, don't filter anyone", 0, true, 0.0);
	gCV_MVPRankOnes_Slow = new Convar("shavit_rankings_mvprankones_slow", "1", "Uses a slower but more featureful MVP counting system.\nEnables the WR Holder ranks & counts for every style & track.\nYou probably won't need to change this unless you have hundreds of thousands of player times in your database.", 0, true, 0.0, true, 1.0);
	gCV_MVPRankOnes = new Convar("shavit_rankings_mvprankones", "2", "Set the players' amount of MVPs to the amount of #1 times they have.\n0 - Disabled\n1 - Enabled, for all styles.\n2 - Enabled, for default style only.\n(CS:S/CS:GO only)", 0, true, 0.0, true, 2.0);
	gCV_MVPRankOnes_Main = new Convar("shavit_rankings_mvprankones_maintrack", "1", "If set to 0, all tracks will be counted for the MVP stars.\nOtherwise, only the main track will be checked.\n\nRequires \"shavit_stats_mvprankones\" set to 1 or above.\n(CS:S/CS:GO only)", 0, true, 0.0, true, 1.0);
	gCV_DefaultTier = new Convar("shavit_rankings_default_tier", "1", "Sets the default tier for new maps added.", 0, true, 0.0, true, 10.0);
	gCV_DefaultMaxVelocity = new Convar("shavit_rankings_default_maxvelocity", "3500.0", "Sets the default sv_maxvelocity for new maps added.", 0, true, 0.0, false, 0.0);
	gCV_MinMaxVelocity = new Convar("shavit_rankings_min_maxvelocity", "3499.9", "Sets the minimum sv_maxvelocity value.", 0, true, 0.0, false, 0.0);

	sv_maxvelocity = FindConVar("sv_maxvelocity");

	Convar.AutoExecConfig();

	LoadTranslations("common.phrases");
	LoadTranslations("shavit-common.phrases");
	LoadTranslations("shavit-rankings.phrases");

	// tier cache
	gA_ValidMaps = new ArrayList(ByteCountToCells(PLATFORM_MAX_PATH));
	gA_MapTiers = new StringMap();

	if(gB_Late)
	{
		Shavit_OnChatConfigLoaded();
		Shavit_OnDatabaseLoaded();
	}

	if (gEV_Type != Engine_TF2)
	{
		CreateTimer(1.0, Timer_MVPs, 0, TIMER_REPEAT);
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	gI_Styles = styles;
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "shavit-stats"))
	{
		gB_Stats = false;
	}
}

public void Shavit_OnDatabaseLoaded()
{
	GetTimerSQLPrefix(gS_MySQLPrefix, 32);
	gH_SQL = Shavit_GetDatabase(gI_Driver);

	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientAuthorized(i))
		{
			OnClientAuthorized(i, "");
		}
	}

	QueryLog(gH_SQL, SQL_Version_Callback,
		gI_Driver == Driver_sqlite
		? "WITH p AS (SELECT COUNT(*) FROM pragma_function_list WHERE name = 'pow') SELECT sqlite_version(), * FROM p;"
		: "SELECT VERSION();");

	if(!gB_TierQueried)
	{
		OnMapStart();
	}
}

void CreateGetWeightedPointsFunction()
{
	if (gCV_WeightingMultiplier.FloatValue == 1.0)
	{
		return;
	}

	char sQuery[2048];
	Transaction trans = new Transaction();

	AddQueryLog(trans, "DROP PROCEDURE IF EXISTS UpdateAllPoints;;"); // old (and very slow) deprecated method
	AddQueryLog(trans, "DROP FUNCTION IF EXISTS GetWeightedPoints;;"); // this is here, just in case we ever choose to modify or optimize the calculation
	AddQueryLog(trans, "DROP FUNCTION IF EXISTS GetRecordPoints;;");

	char sWeightingLimit[30];

	if (gCV_WeightingLimit.IntValue > 0)
	{
		FormatEx(sWeightingLimit, sizeof(sWeightingLimit), "LIMIT %d", gCV_WeightingLimit.IntValue);
	}

	FormatEx(sQuery, sizeof(sQuery),
		"CREATE FUNCTION GetWeightedPoints(steamid INT) " ...
		"RETURNS FLOAT " ...
		"READS SQL DATA " ...
		"BEGIN " ...
		"DECLARE p FLOAT; " ...
		"DECLARE total FLOAT DEFAULT 0.0; " ...
		"DECLARE mult FLOAT DEFAULT 1.0; " ...
		"DECLARE done INT DEFAULT 0; " ...
		"DECLARE cur CURSOR FOR SELECT points FROM %splayertimes WHERE auth = steamid AND points > 0.0 ORDER BY points DESC %s; " ...
		"DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1; " ...
		"OPEN cur; " ...
		"iter: LOOP " ...
			"FETCH cur INTO p; " ...
			"IF done THEN " ...
				"LEAVE iter; " ...
			"END IF; " ...
			"SET total = total + (p * mult); " ...
			"SET mult = mult * %f; " ...
		"END LOOP; " ...
		"CLOSE cur; " ...
		"RETURN total; " ...
		"END;;", gS_MySQLPrefix, sWeightingLimit, gCV_WeightingMultiplier.FloatValue);


	AddQueryLog(trans, sQuery);

	gH_SQL.Execute(trans, Trans_RankingsSetupSuccess, Trans_RankingsSetupError, 0, DBPrio_High);
}

public void Trans_RankingsSetupError(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Your Mysql/Mariadb didn't let us create the GetWeightedPoints function. Either update your DB version so it doesn't need GetWeightedPoints (to 8.0 or 10.2), fix your DB permissions, OR set `shavit_rankings_weighting` to `1.0`.");
	LogError("Timer (rankings) error %d/%d. Reason: %s", failIndex, numQueries, error);
	SetFailState("Read the error log");
}

public void Trans_RankingsSetupSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	OnMapStart();
}

public void OnClientConnected(int client)
{
	ranking_t empty_ranking;
	gA_Rankings[client] = empty_ranking;
}

public void OnClientAuthorized(int client, const char[] auth)
{
	if (gH_SQL && !IsFakeClient(client))
	{
		if (gB_WRHolderTablesMade)
		{
			UpdateWRs(client);
		}

		UpdatePlayerRank(client, true);
	}
}

public void OnMapStart()
{
	GetLowercaseMapName(gS_Map);
	Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount()); // just in case :)

	if (gH_SQL == null)
	{
		return;
	}

	if (gB_WRHolderTablesMade && !gB_WRHoldersRefreshed)
	{
		RefreshWRHolders();
	}

	// do NOT keep running this more than once per map, as UpdateAllPoints() is called after this eventually and locks up the database while it is running
	if (gB_TierQueried)
	{
		return;
	}

	RefreshMapSettings();

	if (gB_SqliteHatesPOW && gCV_WeightingMultiplier.FloatValue < 1.0)
	{
		LogError("Rankings Weighting multiplier set but sqlite extension isn't supported. Try using db.sqlite.ext from Sourcemod 1.12 or higher.");
	}

	if (gH_Top100Menu == null)
	{
		UpdateTop100();
	}
}

public void RefreshMapSettings()
{
	// Default tier.
	// I won't repeat the same mistake blacky has done with tier 3 being default..
	gI_Tier = gCV_DefaultTier.IntValue;
	gF_MaxVelocity = gCV_DefaultMaxVelocity.FloatValue;
	sv_maxvelocity.FloatValue = gF_MaxVelocity;

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "SELECT map, tier, maxvelocity FROM %smaptiers ORDER BY map ASC;", gS_MySQLPrefix);
	QueryLog(gH_SQL, SQL_FillMapSettingCache_Callback, sQuery, 0, DBPrio_High);

	gB_TierQueried = true;
}

public void SQL_FillMapSettingCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, fill tier cache) error! Reason: %s", error);

		return;
	}

	gA_ValidMaps.Clear();
	gA_MapTiers.Clear();

	while(results.FetchRow())
	{
		char sMap[PLATFORM_MAX_PATH];
		results.FetchString(0, sMap, sizeof(sMap));
		LowercaseString(sMap);

		int tier = results.FetchInt(1);

		gA_MapTiers.SetValue(sMap, tier);
		gA_ValidMaps.PushString(sMap);

		if(StrEqual(sMap, gS_Map))
		{
			gF_MaxVelocity = results.FetchFloat(2);
			sv_maxvelocity.FloatValue = gF_MaxVelocity;
		}

		Call_StartForward(gH_Forwards_OnTierAssigned);
		Call_PushString(sMap);
		Call_PushCell(tier);
		Call_Finish();
	}

	if (!gA_MapTiers.GetValue(gS_Map, gI_Tier))
	{
#if USE_SHMAPTIERS
		GetMapInfoFromSurfHeaven(gS_Map);
#endif

		Call_StartForward(gH_Forwards_OnTierAssigned);
		Call_PushString(gS_Map);
		Call_PushCell(gI_Tier);
		Call_Finish();

		char sQuery[512];
		FormatEx(sQuery, sizeof(sQuery), "REPLACE INTO %smaptiers (map, tier, maxvelocity) VALUES ('%s', %d, %f);", gS_MySQLPrefix, gS_Map, gI_Tier, gCV_DefaultMaxVelocity.FloatValue);
		QueryLog(gH_SQL, SQL_SetMapTier_Callback, sQuery, 0, DBPrio_High);
	}
}

public void OnMapEnd()
{
	gB_TierQueried = false;
	gB_WRHoldersRefreshed = false;
	gB_WRHoldersRefreshedTimer = false;
	gB_WorldRecordsCached = false;
}

#if USE_SHMAPTIERS	
public Action Command_UseSHTier(int client, int args)
{
	Shavit_PrintToChat(client, "Getting map tiers from Surf Heaven.");
	GetMapInfoFromSurfHeaven(gS_Map);
	Shavit_LogMessage("%L - set `%s` tier to surf heaven map tier", client, gS_Map);

	return Plugin_Handled;
}
#endif

public void Shavit_OnWRDeleted(int style, int id, int track, int stage, int accountid, const char[] mapname)
{
	if (!StrEqual(gS_Map, mapname))
	{
		return;
	}

	char sQuery[1024];
	// bUseCurrentMap=true because shavit-wr should maybe have updated the wr even through the updatewrcache query hasn't run yet
	FormatRecalculate(true, track, stage, style, sQuery, sizeof(sQuery));
	QueryLog(gH_SQL, SQL_Recalculate_Callback, sQuery, (style << 8) | track, DBPrio_High);

	UpdateAllPoints(true);
}

public void Shavit_OnWorldRecordsCached()
{
	gB_WorldRecordsCached = true;
}

public Action Timer_MVPs(Handle timer)
{
	if (gCV_MVPRankOnes.IntValue == 0)
	{
		return Plugin_Continue;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			CS_SetMVPCount(i, Shavit_GetWRCount(i, -1, -1, true));
		}
	}

	return Plugin_Continue;
}

void UpdateWRs(int client)
{
	int iSteamID = GetSteamAccountID(client);

	if(iSteamID == 0)
	{
		return;
	}

	char sQuery[512];

	if (gCV_MVPRankOnes_Slow.BoolValue)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"     SELECT *, 0 as track, 0 as type FROM %swrhrankmain  WHERE auth = %d \
			UNION SELECT *, 1 as track, 0 as type FROM %swrhrankbonus WHERE auth = %d \
			UNION SELECT *, -1,         1 as type FROM %swrhrankall   WHERE auth = %d \
			UNION SELECT *, -1,         2 as type FROM %swrhrankcvar  WHERE auth = %d;",
			gS_MySQLPrefix, iSteamID, gS_MySQLPrefix, iSteamID, gS_MySQLPrefix, iSteamID, gS_MySQLPrefix, iSteamID);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"SELECT 0 as wrrank, -1 as style, auth, COUNT(*), -1 as track, 2 as type FROM %swrs WHERE auth = %d %s %s;",
			gS_MySQLPrefix,
			iSteamID,
			(gCV_MVPRankOnes.IntValue == 2)  ? "AND style = 0" : "",
			(gCV_MVPRankOnes_Main.BoolValue) ? "AND track = 0" : ""
		);
	}

	QueryLog(gH_SQL, SQL_GetWRs_Callback, sQuery, GetClientSerial(client));
}

public void SQL_GetWRs_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("SQL_GetWRs_Callback failed. Reason: %s", error);
		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	while (results.FetchRow())
	{
		int wrrank  = results.FetchInt(0);
		int style   = results.FetchInt(1);
		//int auth    = results.FetchInt(2);
		int wrcount = results.FetchInt(3);
		int track   = results.FetchInt(4);
		int type    = results.FetchInt(5);

		if (type == 0)
		{
			int index = STYLE_LIMIT*track + style;
			gA_Rankings[client].iWRAmount[index] = wrcount;
			gA_Rankings[client].iWRHolderRank[index] = wrrank;
		}
		else if (type == 1)
		{
			gA_Rankings[client].iWRAmountAll = wrcount;
			gA_Rankings[client].iWRHolderRankAll = wrcount;
		}
		else if (type == 2)
		{
			gA_Rankings[client].iWRAmountCvar = wrcount;
			gA_Rankings[client].iWRHolderRankCvar = wrrank;
		}
	}
}

public Action Command_Tier(int client, int args)
{
	int tier = gI_Tier;

	char sMap[PLATFORM_MAX_PATH];

	if(args == 0)
	{
		sMap = gS_Map;
	}
	else
	{
		GetCmdArgString(sMap, sizeof(sMap));
		LowercaseString(sMap);

		if(!GuessBestMapName(gA_ValidMaps, sMap, sMap) || !gA_MapTiers.GetValue(sMap, tier))
		{
			Shavit_PrintToChat(client, "%t", "Map was not found", sMap);
			return Plugin_Handled;
		}
	}

	Shavit_PrintToChat(client, "%T", "CurrentTier", client, gS_ChatStrings.sVariable, sMap, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, tier, gS_ChatStrings.sText);

	return Plugin_Handled;
}

public Action Command_Rank(int client, int args)
{
	int target = client;

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		target = FindTarget(client, sArgs, true, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}

	if(gA_Rankings[target].fPoints == 0.0)
	{
		Shavit_PrintToChat(client, "%T", "Unranked", client, gS_ChatStrings.sVariable2, target, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	Shavit_PrintToChat(client, "%T", "Rank", client, gS_ChatStrings.sVariable2, target, gS_ChatStrings.sText,
		gS_ChatStrings.sVariable, (gA_Rankings[target].iRank > gI_RankedPlayers)? gI_RankedPlayers:gA_Rankings[target].iRank, gS_ChatStrings.sText,
		gI_RankedPlayers,
		gS_ChatStrings.sVariable, gA_Rankings[target].fPoints, gS_ChatStrings.sText);

	return Plugin_Handled;
}

public Action Command_Top(int client, int args)
{
	if(gH_Top100Menu != null)
	{
		gH_Top100Menu.SetTitle("%T (%d)\n ", "Top100", client, gI_RankedPlayers);
		gH_Top100Menu.Display(client, MENU_TIME_FOREVER);
	}

	return Plugin_Handled;
}

public int MenuHandler_Top(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, 32);

		if(gB_Stats && !StrEqual(sInfo, "-1"))
		{
			FakeClientCommand(param1, "sm_profile [U:1:%s]", sInfo);
		}
	}

	return 0;
}

public Action Command_SetMaxVelocity(int client, int args)
{
	char sArg[8];
	GetCmdArg(1, sArg, 8);

	float fMaxVelocity = StringToFloat(sArg);
	float fOldMaxVelocity = sv_maxvelocity.FloatValue;

	if(args == 0 || fMaxVelocity < gCV_MinMaxVelocity.FloatValue)
	{
		char sMessage[64];
		Format(sMessage, 64, "sm_setmaxvelocity <value> (%.0f or greater) [map]", gCV_MinMaxVelocity.FloatValue);
		ReplyToCommand(client, "%T", "ArgumentsMissing", client, sMessage);

		return Plugin_Handled;
	}

	char map[PLATFORM_MAX_PATH];

	if (args < 2)
	{
		gF_MaxVelocity = fMaxVelocity;
		map = gS_Map;
		sv_maxvelocity.FloatValue = gF_MaxVelocity;
	}
	else
	{
		GetCmdArg(2, map, sizeof(map));
		TrimString(map);
		LowercaseString(map);

		if (!map[0])
		{
			Shavit_PrintToChat(client, "Invalid map name");
			return Plugin_Handled;
		}
	}

	for(int i = 0; i < MaxClients; i++)
	{
		Shavit_PrintToChat(i, "%T", "SetMaxVelocity", i, gS_ChatStrings.sVariable2, fOldMaxVelocity, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, fMaxVelocity, gS_ChatStrings.sText);
	}
	
	Shavit_LogMessage("%L - set sv_maxvelocity of `%s` to %f", client, gS_Map, fMaxVelocity);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "REPLACE INTO %smaptiers (map, maxvelocity) VALUES ('%s', %f);", gS_MySQLPrefix, map, fMaxVelocity);

	QueryLog(gH_SQL, SQL_SetMapMaxVelocity_Callback, sQuery, fMaxVelocity);

	return Plugin_Handled;
}

public void SQL_SetMapMaxVelocity_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, set map maxvelocity) error! Reason: %s", error);

		return;
	}
}

public Action Command_SetTier(int client, int args)
{
	char sArg[8];
	GetCmdArg(1, sArg, 8);

	int tier = StringToInt(sArg);

	if(args == 0 || tier < 1 || tier > 10)
	{
		ReplyToCommand(client, "%T", "ArgumentsMissing", client, "sm_settier <tier> (1-10) [map]");

		return Plugin_Handled;
	}

	char map[PLATFORM_MAX_PATH];

	if (args < 2)
	{
		gI_Tier = tier;
		map = gS_Map;
	}
	else
	{
		GetCmdArg(2, map, sizeof(map));
		TrimString(map);
		LowercaseString(map);

		if (!map[0])
		{
			Shavit_PrintToChat(client, "Invalid map name");
			return Plugin_Handled;
		}
	}

	gA_MapTiers.SetValue(map, tier);

	Call_StartForward(gH_Forwards_OnTierAssigned);
	Call_PushString(map);
	Call_PushCell(tier);
	Call_Finish();

	Shavit_PrintToChat(client, "%T", "SetTier", client, gS_ChatStrings.sVariable2, tier, gS_ChatStrings.sText);
	Shavit_LogMessage("%L - set tier of `%s` to %d", client, map, tier);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "REPLACE INTO %smaptiers (map, tier) VALUES ('%s', %d);", gS_MySQLPrefix, map, tier);

	DataPack data = new DataPack();
	data.WriteCell(client ? GetClientSerial(client) : 0);
	data.WriteString(map);

	QueryLog(gH_SQL, SQL_SetMapTier_Callback, sQuery, data);

	return Plugin_Handled;
}

public void SQL_SetMapTier_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if(results == null)
	{
		LogError("Timer (rankings, set map tier) error! Reason: %s", error);

		return;
	}

	if (data == null)
	{
		return;
	}

	int serial;
	char map[PLATFORM_MAX_PATH];

	data.Reset();
	serial = data.ReadCell();
	data.ReadString(map, sizeof(map));

	if (StrEqual(map, gS_Map))
	{
		ReallyRecalculateCurrentMap();
	}
	else
	{
		RecalculateSpecificMap(map, serial);
	}

	delete data;
}

public Action Command_RecalcMap(int client, int args)
{
	ReallyRecalculateCurrentMap();

	ReplyToCommand(client, "Recalc started.");

	return Plugin_Handled;
}

// You can use Sourcepawn_GetRecordPoints() as a reference for how the queries calculate points.
void FormatRecalculate(bool bUseCurrentMap, int track, int stage, int style, char[] sQuery, int sQueryLen, const char[] map = "")
{
	float fMultiplier = Shavit_GetStyleSettingFloat(style, "rankingmultiplier");

	char sTable[32];
	FormatEx(sTable, sizeof(sTable), "%s", stage == 0 ? "playertimes":"stagetimes");

	if (Shavit_GetStyleSettingBool(style, "unranked") || fMultiplier == 0.0)
	{
		FormatEx(sQuery, sQueryLen,
			"UPDATE %s%s SET points = 0 WHERE style = %d AND track %c 0 %s%s%s;",
			gS_MySQLPrefix, sTable,
			style,
			(track > 0) ? '>' : '=',
			(bUseCurrentMap) ? "AND map = '" : "",
			(bUseCurrentMap) ? gS_Map : "",
			(bUseCurrentMap) ? "'" : ""
		);

		return;
	}

	float fMaxRankPoint;
	float fBaiscFinishPoint;
	float fExtraFinishPoint = 0.0;
	float fTier = float(gI_Tier);

	if(track >= Track_Bonus)
	{
		fTier = 1.0;
		fMaxRankPoint = gCV_MaxRankPoints_Bonus.FloatValue;
		fBaiscFinishPoint = gCV_BasicFinishPoints_Bonus.FloatValue;
	}
	else if(stage == 0)
	{
		fMaxRankPoint = gCV_MaxRankPoints_Main.FloatValue;
		fBaiscFinishPoint = gCV_BasicFinishPoints_Main.FloatValue;
		fExtraFinishPoint = fTier * Pow(max(0.0, fTier-4.0), 2.0) * fBaiscFinishPoint;
	}
	else 
	{
		fMaxRankPoint = gCV_MaxRankPoints_Stage.FloatValue;
		fBaiscFinishPoint = gCV_BasicFinishPoints_Stage.FloatValue == 0.0 ? fTier : gCV_BasicFinishPoints_Stage.FloatValue;
	}

	float fFinishPoint = fBaiscFinishPoint * fTier;

	char sStageFilter[32];
	if(stage > 0) FormatEx(sStageFilter, sizeof(sStageFilter), "AND stage = %d", stage);

	if (bUseCurrentMap)
	{
		FormatEx(sQuery, sQueryLen,
			"WITH RankedPT AS "...
			"(SELECT id, %f / RANK() OVER (ORDER BY time ASC) AS points FROM %s%s WHERE map = '%s' AND track = %d AND style = %d %s) "...
			"UPDATE %s%s SET points = RankedPT.points + %f FROM RankedPT WHERE %s.id = RankedPT.id;",
			fMaxRankPoint, gS_MySQLPrefix, sTable, gS_Map, track, style, sStageFilter, gS_MySQLPrefix, sTable, fFinishPoint + fExtraFinishPoint, sTable);
	}
	else
	{
		char mapfilter[50+PLATFORM_MAX_PATH];
		if (map[0]) FormatEx(mapfilter, sizeof(mapfilter), "AND %s.map = '%s'", sTable, map);

		char sPointCalculate[256];

		if(stage > 0)
		{
			if(gCV_BasicFinishPoints_Stage.FloatValue == 0.0)
			{
				FormatEx(sPointCalculate, sizeof(sPointCalculate), "RankedPT.tier * RankedPT.tier");				
			}
			else
			{
				FormatEx(sPointCalculate, sizeof(sPointCalculate), "RankedPT.tier * %f", fBaiscFinishPoint);
			}
		}
		else if(track == Track_Main)
		{
			FormatEx(sPointCalculate, sizeof(sPointCalculate), "(%f * RankedPT.tier) + (RankedPT.tier * Pow(Max(0.0, RankedPT.tier - 4.0), 2.0) * %f)", 
			fBaiscFinishPoint, fBaiscFinishPoint);
		}
		else
		{
			FormatEx(sPointCalculate, sizeof(sPointCalculate), "%f", fBaiscFinishPoint);
		}

		FormatEx(sQuery, sQueryLen,
			"WITH RankedPT AS "...
			"(SELECT id, CAST(tier AS FLOAT) as tier, %f / RANK() OVER (ORDER BY time ASC) AS points "...
			"FROM %s%s JOIN %smaptiers AS MT ON %s.map = MT.map WHERE track = %d AND style = %d %s %s ) "...
			"UPDATE %s%s SET points = (RankedPT.points + (%s)) * %f "...
			"FROM RankedPT WHERE %s.id = RankedPT.id;",
			fMaxRankPoint, gS_MySQLPrefix, sTable, gS_MySQLPrefix, sTable, 
			track, style, mapfilter, sStageFilter, gS_MySQLPrefix, sTable, sPointCalculate, fMultiplier, sTable);
	}
}

// it didnt work on shavit surf timer
// public Action Command_RecalcAll(int client, int args)
// {
// 	ReplyToCommand(client, "- Started recalculating points for all maps. Check console for output.");

// 	Transaction trans = new Transaction();
// 	char sQuery[1024];

// 	FormatEx(sQuery, sizeof(sQuery), "UPDATE %splayertimes SET points = 0;", gS_MySQLPrefix);
// 	AddQueryLog(trans, sQuery);
// 	FormatEx(sQuery, sizeof(sQuery), "UPDATE %sstagetimes SET points = 0;", gS_MySQLPrefix);
// 	AddQueryLog(trans, sQuery);
// 	FormatEx(sQuery, sizeof(sQuery), "UPDATE %susers SET points = 0;", gS_MySQLPrefix);
// 	AddQueryLog(trans, sQuery);

// 	for(int i = 0; i < gI_Styles; i++)
// 	{
// 		if (!Shavit_GetStyleSettingBool(i, "unranked") && Shavit_GetStyleSettingFloat(i, "rankingmultiplier") != 0.0)
// 		{
// 			for (int j = 0; j < TRACKS_SIZE; j++)
// 			{
// 				FormatRecalculate(false, j, 0, i, sQuery, sizeof(sQuery));
// 			}

// 			for (int k = 0; k <= Shavit_GetStageCount(Track_Main); k++)
// 			{
// 				FormatRecalculate(false, Track_Main, k, i, sQuery, sizeof(sQuery));
// 			}
// 		}
// 	}

// 	gH_SQL.Execute(trans, Trans_OnRecalcSuccess, Trans_OnRecalcFail, (client == 0)? 0:GetClientSerial(client));

// 	return Plugin_Handled;
// }

public void Trans_OnRecalcSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	int client = (data == 0)? 0:GetClientFromSerial(data);

	if(client != 0)
	{
		SetCmdReplySource(SM_REPLY_TO_CONSOLE);
	}

	ReplyToCommand(client, "- Finished recalculating all points. Recalculating user points, top 100 and user cache.");

	UpdateAllPoints(true);
}

public void Trans_OnRecalcFail(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (rankings) error! Recalculation failed. Reason: %s", error);
}

void RecalculateSpecificMap(const char[] map, int serial)
{
	Transaction trans = new Transaction();
	char sQuery[1024];

	// Only maintrack times because bonus times aren't tiered.
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %splayertimes SET points = 0 WHERE map = '%s' AND track = 0;", gS_MySQLPrefix, map);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %sstagetimes SET points = 0 WHERE map = '%s';", gS_MySQLPrefix, map);
	AddQueryLog(trans, sQuery);

	for(int i = 0; i < gI_Styles; i++)
	{
		if (!Shavit_GetStyleSettingBool(i, "unranked") && Shavit_GetStyleSettingFloat(i, "rankingmultiplier") != 0.0)
		{
			for (int j = 0; j < TRACKS_SIZE; j++)
			{
				FormatRecalculate(false, j, 0, i, sQuery, sizeof(sQuery), map);
				AddQueryLog(trans, sQuery);
			}

			for (int k = 0; k <= Shavit_GetStageCount(Track_Main); k++)
			{
				FormatRecalculate(false, Track_Main, k, i, sQuery, sizeof(sQuery), map);
				AddQueryLog(trans, sQuery);
			}
		}
	}

	gH_SQL.Execute(trans, Trans_OnRecalcSuccess, Trans_OnRecalcFail, serial);
}

void ReallyRecalculateCurrentMap()
{
	#if defined DEBUG
	LogError("DEBUG: 5xxx (ReallyRecalculateCurrentMap)");
	#endif

	Transaction trans = new Transaction();
	char sQuery[1024];

	FormatEx(sQuery, sizeof(sQuery), "UPDATE %splayertimes SET points = 0 WHERE map = '%s';", gS_MySQLPrefix, gS_Map);
	AddQueryLog(trans, sQuery);
	FormatEx(sQuery, sizeof(sQuery), "UPDATE %sstagetimes SET points = 0 WHERE map = '%s';", gS_MySQLPrefix, gS_Map);
	AddQueryLog(trans, sQuery);

	for(int i = 0; i < gI_Styles; i++)
	{
		if (!Shavit_GetStyleSettingBool(i, "unranked") && Shavit_GetStyleSettingFloat(i, "rankingmultiplier") != 0.0)
		{
			for (int j = 0; j < TRACKS_SIZE; j++)
			{
				FormatRecalculate(true, j, 0, i, sQuery, sizeof(sQuery));
				AddQueryLog(trans, sQuery);
			}

			for (int k = 0; k <= Shavit_GetStageCount(Track_Main); k++)
			{
				FormatRecalculate(true, Track_Main, k, i, sQuery, sizeof(sQuery));
				AddQueryLog(trans, sQuery);
			}
		}
	}

	gH_SQL.Execute(trans, Trans_OnReallyRecalcSuccess, Trans_OnReallyRecalcFail, 0);
}

public void Trans_OnReallyRecalcSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	UpdateAllPoints(true, gS_Map);
}

public void Trans_OnReallyRecalcFail(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (rankings) error! ReallyRecalculateCurrentMap failed. Reason: %s", error);
}

public void Shavit_OnFinishStage_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int stage, float oldtime, float perfs, float avgvel, float maxvel, int timestamp)
{
	if (Shavit_GetStyleSettingBool(style, "unranked") || Shavit_GetStyleSettingFloat(style, "rankingmultiplier") == 0.0)
	{
		return;
	}

	if (rank >= 20)
	{
		UpdatePointsForSinglePlayer(client);
		return;
	}

	#if defined DEBUG
	PrintToServer("Recalculating points. (%s, %d, %d)", map, track, style);
	#endif

	char sQuery[1024];
	FormatRecalculate(true, Track_Main, stage, style, sQuery, sizeof(sQuery));

	QueryLog(gH_SQL, SQL_Recalculate_Callback, sQuery, (style << 8) | Track_Main, DBPrio_High);
	UpdateAllPoints(true, gS_Map, Track_Main);
}

public void Shavit_OnFinish_Post(int client, int style, float time, int jumps, int strafes, float sync, int rank, int overwrite, int track)
{
	if (Shavit_GetStyleSettingBool(style, "unranked") || Shavit_GetStyleSettingFloat(style, "rankingmultiplier") == 0.0)
	{
		return;
	}

	if (rank >= 20)
	{
		UpdatePointsForSinglePlayer(client);
		return;
	}

	#if defined DEBUG
	PrintToServer("Recalculating points. (%s, %d, %d)", map, track, style);
	#endif

	char sQuery[1024];
	FormatRecalculate(true, track, 0, style, sQuery, sizeof(sQuery));	// recal points here

	QueryLog(gH_SQL, SQL_Recalculate_Callback, sQuery, (style << 8) | track, DBPrio_High);
	UpdateAllPoints(true, gS_Map, track);
}

public void SQL_Recalculate_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	int track = data & 0xFF;
	int style = data >> 8;

	if(results == null)
	{
		LogError("Timer (rankings, recalculate map points, %s, style=%d) error! Reason: %s", (track == Track_Main) ? "main" : "bonus", style, error);

		return;
	}

	#if defined DEBUG
	PrintToServer("Recalculated (%s, style=%d).", (track == Track_Main) ? "main_" : "bonus", style);
	#endif
}

void UpdatePointsForSinglePlayer(int client)
{
	int auth = GetSteamAccountID(client);

	char sQuery[1024];

	if (gCV_WeightingMultiplier.FloatValue == 1.0 || gB_SqliteHatesPOW)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"UPDATE %susers SET points = (SELECT SUM(points) FROM "...
			"(SELECT points, auth FROM %splayertimes UNION ALL SELECT points, auth FROM %sstagetimes) PT WHERE PT.auth = %d) WHERE users.auth = %d;",
			gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, auth, auth);
	}
	else if (gB_SQLWindowFunctions)
	{
		char sLimit[30];
		if (gCV_WeightingLimit.IntValue > 0)
			FormatEx(sLimit, sizeof(sLimit), "LIMIT %d", gCV_WeightingLimit.IntValue);

		FormatEx(sQuery, sizeof(sQuery),
		    "UPDATE %susers SET points = (\n"
		... "  SELECT SUM(points2) FROM (\n"
		... "    SELECT (points * POW(%f, ROW_NUMBER() OVER (ORDER BY points DESC) - 1)) as points2\n"
		... "    FROM (SELECT auth, pints, FROM %splayertimes\n"
		... "	 UNION ALL SELECT auth, points FROM %sstagetimes)\n"
		... "    WHERE auth = %d AND points > 0\n"
		... "    ORDER BY points DESC %s\n"
		... "  ) as t\n"
		... ") WHERE auth = %d;",
			gS_MySQLPrefix,
			gCV_WeightingMultiplier.FloatValue,
			gS_MySQLPrefix,
			gS_MySQLPrefix,
			auth,
			sLimit,
			auth
		);
	}
	else // We should only be here if mysql :)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"UPDATE %susers SET points = GetWeightedPoints(auth) WHERE auth = %d;",
			gS_MySQLPrefix, auth);
	}

	QueryLog(gH_SQL, SQL_UpdateAllPoints_Callback, sQuery, GetClientSerial(client));
}

void UpdateAllPoints(bool recalcall=false, char[] map="", int track=-1)
{
	#if defined DEBUG
	LogError("DEBUG: 6 (UpdateAllPoints)");
	#endif
	char sQuery[1024];
	char sLastLogin[69], sLimit[30], sMapWhere[512], sTrackWhere[64];

	if (track != -1)
		FormatEx(sTrackWhere, sizeof(sTrackWhere), "track = %d", track);
	if (map[0])
		FormatEx(sMapWhere, sizeof(sMapWhere), "map = '%s'", map);

	if (!recalcall && gCV_LastLoginRecalculate.IntValue > 0)
	{
		FormatEx(sLastLogin, sizeof(sLastLogin), "lastlogin > %d", (GetTime() - gCV_LastLoginRecalculate.IntValue * 60));
	}

	if (gCV_WeightingLimit.IntValue > 0)
		FormatEx(sLimit, sizeof(sLimit), "LIMIT %d", gCV_WeightingLimit.IntValue);

	if (gCV_WeightingMultiplier.FloatValue == 1.0 || gB_SqliteHatesPOW)
	{
		if (gI_Driver == Driver_sqlite)
		{
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %susers AS U SET points = P.total FROM (SELECT auth, SUM(points) AS total "...
				"FROM (SELECT points, auth FROM %splayertimes UNION ALL SELECT points, auth FROM %sstagetimes) GROUP BY auth) P WHERE U.auth = P.auth %s %s;",
				gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix,
				(sLastLogin[0] != 0) ? "AND " : "", sLastLogin);
		}
		else
		{
			FormatEx(sQuery, sizeof(sQuery),
				"UPDATE %susers AS U INNER JOIN (SELECT auth, SUM(points) AS total "...
				"FROM (SELECT points, auth FROM %splayertimes UNION ALL SELECT points, auth FROM %sstagetimes) GROUP BY auth) P ON U.auth = P.auth SET U.points = P.total %s %s;",
				gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix,
				(sLastLogin[0] != 0) ? "WHERE" : "", sLastLogin);
		}
	}
	else if (gB_SQLWindowFunctions && gI_Driver == Driver_mysql)
	{
		if (sLastLogin[0])
			Format(sLastLogin, sizeof(sLastLogin), "u2.%s", sLastLogin);

		// fuck you mysql
		FormatEx(sQuery, sizeof(sQuery),
		    "UPDATE %susers AS u, (\n"
		... "  SELECT auth, SUM(t.points2) as pp FROM (\n"
		... "    SELECT p.auth, (p.points * POW(%f, ROW_NUMBER() OVER (PARTITION BY p.auth ORDER BY p.points DESC) - 1)) as points2\n"
		... "    FROM %splayertimes AS p\n"
		... "    JOIN %susers AS u2\n"
		... "     ON u2.auth = p.auth %s %s\n"
		... "    WHERE p.points > 0 AND p.auth IN (SELECT DISTINCT auth FROM %splayertimes %s %s %s %s)\n"
		... "    ORDER BY p.points DESC %s\n"
		... "  ) AS t\n"
		... "  GROUP by auth\n"
		... ") AS a\n"
		... "SET u.points = a.pp\n"
		... "WHERE u.auth = a.auth;",
			gS_MySQLPrefix,
			gCV_WeightingMultiplier.FloatValue,
			gS_MySQLPrefix,
			gS_MySQLPrefix,
			sLastLogin[0] ? "AND" : "", sLastLogin,
			gS_MySQLPrefix,
			(sMapWhere[0] || sTrackWhere[0]) ? "WHERE" : "",
			sMapWhere,
			(sMapWhere[0] && sTrackWhere[0]) ? "AND" : "",
			sTrackWhere,
			sLimit); // TODO: Remove/move sLimit?
	}
	else if (gB_SQLWindowFunctions)
	{
		FormatEx(sQuery, sizeof(sQuery),
		    "UPDATE %susers AS u\n"
		... "SET points = (\n"
		... "  SELECT SUM(points2) FROM (\n"
		... "    SELECT (points * POW(%f, ROW_NUMBER() OVER (ORDER BY points DESC) - 1)) AS points2\n"
		... "    FROM %splayertimes\n"
		... "				"
		... "    WHERE auth = u.auth AND points > 0\n"
		... "    ORDER BY points DESC %s\n"
		... "  ) AS t\n"
		... ") WHERE %s %s auth IN\n"
		... "  (SELECT DISTINCT auth FROM %splayertimes %s %s %s %s);",
			gS_MySQLPrefix,
			gCV_WeightingMultiplier.FloatValue,
			gS_MySQLPrefix,
			sLimit, // TODO: Remove/move sLimit?
			sLastLogin, sLastLogin[0] ? "AND" : "",
			gS_MySQLPrefix,
			(sMapWhere[0] || sTrackWhere[0]) ? "WHERE" : "",
			sMapWhere,
			(sMapWhere[0] && sTrackWhere[0]) ? "AND" : "",
			sTrackWhere);
	}
	else // !gB_SQLWindowFunctions && gI_Driver == Driver_mysql
	{
		FormatEx(sQuery, sizeof(sQuery),
			"UPDATE %susers SET points = GetWeightedPoints(auth) WHERE %s %s auth IN (SELECT DISTINCT auth FROM %splayertimes %s %s %s %s);",
			gS_MySQLPrefix,
			sLastLogin, (sLastLogin[0] != 0) ? "AND" : "",
			gS_MySQLPrefix,
			(sMapWhere[0] || sTrackWhere[0]) ? "WHERE" : "",
			sMapWhere,
			(sMapWhere[0] && sTrackWhere[0]) ? "AND" : "",
			sTrackWhere);
	}

	QueryLog(gH_SQL, SQL_UpdateAllPoints_Callback, sQuery);
}

public void SQL_UpdateAllPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update all points) error! Reason: %s", error);

		return;
	}

	UpdateTop100();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsClientAuthorized(i))
		{
			UpdatePlayerRank(i, false);
		}
	}
}

void UpdatePlayerRank(int client, bool first)
{
	int iSteamID = 0;

	if((iSteamID = GetSteamAccountID(client)) != 0)
	{
		// if there's any issue with this query,
		// add "ORDER BY points DESC " before "LIMIT 1"
		char sQuery[512];
		FormatEx(sQuery, 512, "SELECT u2.points, COUNT(*) FROM %susers u1 JOIN (SELECT points FROM %susers WHERE auth = %d) u2 WHERE u1.points >= u2.points;",
			gS_MySQLPrefix, gS_MySQLPrefix, iSteamID);

		DataPack hPack = new DataPack();
		hPack.WriteCell(GetClientSerial(client));
		hPack.WriteCell(first);

		QueryLog(gH_SQL, SQL_UpdatePlayerRank_Callback, sQuery, hPack, DBPrio_Low);
	}
}

public void SQL_UpdatePlayerRank_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack hPack = view_as<DataPack>(data);
	hPack.Reset();

	int iSerial = hPack.ReadCell();
	bool bFirst = view_as<bool>(hPack.ReadCell());
	delete hPack;

	if(results == null)
	{
		LogError("Timer (rankings, update player rank) error! Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(iSerial);

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		gA_Rankings[client].fPoints = results.FetchFloat(0);
		gA_Rankings[client].iRank = (gA_Rankings[client].fPoints > 0.0)? results.FetchInt(1):0;

		Call_StartForward(gH_Forwards_OnRankAssigned);
		Call_PushCell(client);
		Call_PushCell(gA_Rankings[client].iRank);
		Call_PushCell(gA_Rankings[client].fPoints);
		Call_PushCell(bFirst);
		Call_Finish();
	}
}

void UpdateTop100()
{
	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery),
		"SELECT * FROM (SELECT COUNT(*) as c, 0 as auth, '' as name, '' as p FROM %susers WHERE points > 0) a \
		UNION ALL \
		SELECT * FROM (SELECT -1 as c, auth, name, FORMAT(points, 2) FROM %susers WHERE points > 0 ORDER BY points DESC LIMIT 100) b;",
		gS_MySQLPrefix, gS_MySQLPrefix);

	QueryLog(gH_SQL, SQL_UpdateTop100_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_UpdateTop100_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update top 100) error! Reason: %s", error);

		return;
	}

	if (!results.FetchRow())
	{
		LogError("Timer (rankings, update top 100 b) error! Reason: failed to fetch first row");
		return;
	}

	gI_RankedPlayers = results.FetchInt(0);

	delete gH_Top100Menu;
	gH_Top100Menu = new Menu(MenuHandler_Top);

	int row = 0;

	while(results.FetchRow())
	{
		char sSteamID[32];
		results.FetchString(1, sSteamID, 32);

		char sName[32+1];
		results.FetchString(2, sName, sizeof(sName));

		char sPoints[16];
		results.FetchString(3, sPoints, 16);

		char sDisplay[96];
		FormatEx(sDisplay, 96, "#%d - %s (%s)", (++row), sName, sPoints);
		gH_Top100Menu.AddItem(sSteamID, sDisplay);
	}

	if(gH_Top100Menu.ItemCount == 0)
	{
		char sDisplay[64];
		FormatEx(sDisplay, 64, "%t", "NoRankedPlayers");
		gH_Top100Menu.AddItem("-1", sDisplay);
	}

	gH_Top100Menu.ExitButton = true;
}

bool DoWeHaveWindowFunctions(const char[] sVersion)
{
	float fVersion = StringToFloat(sVersion);

	if (gI_Driver == Driver_sqlite)
	{
		return fVersion >= 3.25; // 2018~
	}
	else if (gI_Driver == Driver_pgsql)
	{
		return fVersion >= 8.4; // 2009~
	}
	else if (gI_Driver == Driver_mysql)
	{
		if (StrContains(sVersion, "MariaDB") != -1)
		{
			return fVersion >= 10.2; // 2016~
		}
		else // mysql then...
		{
			return fVersion >= 8.0; // 2018~
		}
	}

	return false;
}

public void SQL_Version_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null || !results.FetchRow())
	{
		LogError("Timer (rankings) error! Failed to retrieve VERSION(). Reason: %s", error);
	}
	else
	{
		char sVersion[100];
		results.FetchString(0, sVersion, sizeof(sVersion));
		gB_SQLWindowFunctions = DoWeHaveWindowFunctions(sVersion);

		if (gI_Driver == Driver_sqlite)
		{
			gB_SqliteHatesPOW = results.FetchInt(1) == 0;
		}
	}

	if (!gB_SQLWindowFunctions)
	{
		if (gI_Driver == Driver_sqlite)
		{
			SetFailState("sqlite version not supported. Try using db.sqlite.ext from Sourcemod 1.12 or higher.");
		}
		else if (gI_Driver == Driver_pgsql)
		{
			LogError("Okay, really? Your postgres version is from 2014 or earlier... come on, brother...");
			SetFailState("Update postgresql");
		}
		else // mysql
		{
			// Mysql 5.7 is a cancer upon society. EOS is Oct 2023!! Unbelievable.
			// Please update your servers already, nfoservers.
			CreateGetWeightedPointsFunction();
		}
	}

	char sWRHolderRankTrackQueryYuck[] =
		"%s %s%s AS \
			SELECT \
			0 as wrrank, \
			style, auth, COUNT(auth) as wrcount \
			FROM %swrs WHERE track %c 0 GROUP BY style, auth;";

	char sWRHolderRankTrackQueryRANK[] =
		"%s %s%s AS \
			SELECT \
				RANK() OVER(PARTITION BY style ORDER BY COUNT(auth) DESC, auth ASC) \
			as wrrank, \
			style, auth, COUNT(auth) as wrcount \
			FROM %swrs WHERE track %c 0 GROUP BY style, auth;";

	char sWRHolderRankOtherQueryYuck[] =
		"%s %s%s AS \
			SELECT \
			0 as wrrank, \
			-1 as style, auth, COUNT(*) \
			FROM %swrs %s %s %s %s GROUP BY auth;";

	char sWRHolderRankOtherQueryRANK[] =
		"%s %s%s AS \
			SELECT \
				RANK() OVER(ORDER BY COUNT(auth) DESC, auth ASC) \
			as wrrank, \
			-1 as style, auth, COUNT(*) as wrcount \
			FROM %swrs %s %s %s %s GROUP BY auth;";

	char sQuery[800];
	Transaction trans = new Transaction();

	if (gI_Driver == Driver_sqlite)
	{
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankmain;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankbonus;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankall;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
		FormatEx(sQuery, sizeof(sQuery), "DROP VIEW IF EXISTS %swrhrankcvar;", gS_MySQLPrefix);
		AddQueryLog(trans, sQuery);
	}

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankTrackQueryYuck : sWRHolderRankTrackQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankmain", gS_MySQLPrefix, '=');
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankTrackQueryYuck : sWRHolderRankTrackQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankbonus", gS_MySQLPrefix, '>');
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankOtherQueryYuck : sWRHolderRankOtherQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankall", gS_MySQLPrefix, "", "", "", "");
	AddQueryLog(trans, sQuery);

	FormatEx(sQuery, sizeof(sQuery),
		!gB_SQLWindowFunctions ? sWRHolderRankOtherQueryYuck : sWRHolderRankOtherQueryRANK,
		gI_Driver == Driver_sqlite ? "CREATE VIEW IF NOT EXISTS" : "CREATE OR REPLACE VIEW",
		gS_MySQLPrefix, "wrhrankcvar", gS_MySQLPrefix,
		(gCV_MVPRankOnes.IntValue == 2 || gCV_MVPRankOnes_Main.BoolValue) ? "WHERE" : "",
		(gCV_MVPRankOnes.IntValue == 2)  ? "style = 0" : "",
		(gCV_MVPRankOnes.IntValue == 2 && gCV_MVPRankOnes_Main.BoolValue) ? "AND" : "",
		(gCV_MVPRankOnes_Main.BoolValue) ? "track = 0" : "");
	AddQueryLog(trans, sQuery);

	gH_SQL.Execute(trans, Trans_WRHolderRankTablesSuccess, Trans_WRHolderRankTablesError, 0, DBPrio_High);
}

public void Trans_WRHolderRankTablesSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	gB_WRHolderTablesMade = true;

	for(int i = 1; i <= MaxClients; i++)
	{
		if (IsClientConnected(i) && IsClientAuthorized(i))
		{
			UpdateWRs(i);
		}
	}

	RefreshWRHolders();
}

void RefreshWRHolders()
{
	if (gB_WRHoldersRefreshedTimer)
	{
		return;
	}

	gB_WRHoldersRefreshedTimer = true;
	CreateTimer(10.0, Timer_RefreshWRHolders, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RefreshWRHolders(Handle timer, any data)
{
	RefreshWRHoldersActually();
	return Plugin_Stop;
}

void RefreshWRHoldersActually()
{
	char sQuery[1024];

	if (gCV_MVPRankOnes_Slow.BoolValue)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"     SELECT 0 as type, 0 as track, style, COUNT(DISTINCT auth) FROM %swrhrankmain GROUP BY style \
			UNION SELECT 0 as type, 1 as track, style, COUNT(DISTINCT auth) FROM %swrhrankbonus GROUP BY style \
			UNION SELECT 1 as type, -1 as track, -1 as style, COUNT(DISTINCT auth) FROM %swrhrankall \
			UNION SELECT 2 as type, -1 as track, -1 as style, COUNT(DISTINCT auth) FROM %swrhrankcvar;",
			gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix, gS_MySQLPrefix);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"SELECT 2 as type, -1 as track, -1 as style, COUNT(DISTINCT auth) FROM %swrs %s %s %s %s;",
			gS_MySQLPrefix,
			(gCV_MVPRankOnes.IntValue == 2 || gCV_MVPRankOnes_Main.BoolValue) ? "WHERE" : "",
			(gCV_MVPRankOnes.IntValue == 2)  ? "style = 0" : "",
			(gCV_MVPRankOnes.IntValue == 2 && gCV_MVPRankOnes_Main.BoolValue) ? "AND" : "",
			(gCV_MVPRankOnes_Main.BoolValue) ? "track = 0" : ""
		);
	}

	QueryLog(gH_SQL, SQL_GetWRHolders_Callback, sQuery);

	gB_WRHoldersRefreshed = true;
}

public void Trans_WRHolderRankTablesError(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (WR Holder Rank table creation %d/%d) SQL query failed. Reason: %s", failIndex, numQueries, error);
}

public void SQL_GetWRHolders_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (get WR Holder amount) SQL query failed. Reason: %s", error);

		return;
	}

	while (results.FetchRow())
	{
		int type  = results.FetchInt(0);
		int track = results.FetchInt(1);
		int style = results.FetchInt(2);
		int total = results.FetchInt(3);

		if (type == 0)
		{
			gI_WRHolders[track][style] = total;
		}
		else if (type == 1)
		{
			gI_WRHoldersAll = total;
		}
		else if (type == 2)
		{
			gI_WRHoldersCvar = total;
		}
	}
}

public int Native_GetWRCount(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);
	int style = GetNativeCell(3);
	bool usecvars = view_as<bool>(GetNativeCell(4));

	if (usecvars)
	{
		return gA_Rankings[client].iWRAmountCvar;
	}
	else if (track == -1 && style == -1)
	{
		return gA_Rankings[client].iWRAmountAll;
	}

	if (track > Track_Bonus)
	{
		track = Track_Bonus;
	}

	return gA_Rankings[client].iWRAmount[STYLE_LIMIT*track + style];
}

public int Native_GetWRHolders(Handle handler, int numParams)
{
	int track = GetNativeCell(1);
	int style = GetNativeCell(2);
	bool usecvars = view_as<bool>(GetNativeCell(3));

	if (usecvars)
	{
		return gI_WRHoldersCvar;
	}
	else if (track == -1 && style == -1)
	{
		return gI_WRHoldersAll;
	}

	if (track > Track_Bonus)
	{
		track = Track_Bonus;
	}

	return gI_WRHolders[track][style];
}

public int Native_GetWRHolderRank(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);
	int style = GetNativeCell(3);
	bool usecvars = view_as<bool>(GetNativeCell(4));

	if (usecvars)
	{
		return gA_Rankings[client].iWRHolderRankCvar;
	}
	else if (track == -1 && style == -1)
	{
		return gA_Rankings[client].iWRHolderRankAll;
	}

	if (track > Track_Bonus)
	{
		track = Track_Bonus;
	}

	return gA_Rankings[client].iWRHolderRank[STYLE_LIMIT*track + style];
}

public int Native_GetMapTier(Handle handler, int numParams)
{
	int tier = 0;
	char sMap[PLATFORM_MAX_PATH];
	GetNativeString(1, sMap, sizeof(sMap));

	if (!sMap[0])
	{
		return gI_Tier;
	}

	gA_MapTiers.GetValue(sMap, tier);
	return tier;
}

public int Native_GetMapTiers(Handle handler, int numParams)
{
	return view_as<int>(CloneHandle(gA_MapTiers, handler));
}

public int Native_GetPoints(Handle handler, int numParams)
{
	return view_as<int>(gA_Rankings[GetNativeCell(1)].fPoints);
}

public int Native_GetRank(Handle handler, int numParams)
{
	return gA_Rankings[GetNativeCell(1)].iRank;
}

public int Native_GetRankedPlayers(Handle handler, int numParams)
{
	return gI_RankedPlayers;
}

public int Native_Rankings_DeleteMap(Handle handler, int numParams)
{
	char sMap[PLATFORM_MAX_PATH];
	GetNativeString(1, sMap, sizeof(sMap));
	LowercaseString(sMap);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM %smaptiers WHERE map = '%s';", gS_MySQLPrefix, sMap);
	QueryLog(gH_SQL, SQL_DeleteMap_Callback, sQuery, StrEqual(gS_Map, sMap, false), DBPrio_High);
	return 1;
}

public int Native_GuessPointsForTime(Handle plugin, int numParams)
{
	int track = GetNativeCell(1);
	int stage = GetNativeCell(2);
	int style = GetNativeCell(3);
	int rank = GetNativeCell(4);
	int tier = GetNativeCell(5);

	float ppoints = Sourcepawn_GetRecordPoints(
		track,
		stage,
		rank,
		Shavit_GetStyleSettingFloat(style, "rankingmultiplier"),
		float(tier == -1 ? gI_Tier : tier)
	);

	return view_as<int>(ppoints);
}

float Sourcepawn_GetRecordPoints(int track, int stage, int rank, float stylemultiplier, float tier)
{
	float fMaxRankPoint;
	float fBaiscFinishPoint;
	float fExtraFinishPoint = 0.0;

	if(track >= Track_Bonus)
	{
		tier = 1.0;
		fMaxRankPoint = gCV_MaxRankPoints_Bonus.FloatValue;
		fBaiscFinishPoint = gCV_BasicFinishPoints_Bonus.FloatValue;
	}
	else if(stage == 0)
	{
		fMaxRankPoint = gCV_MaxRankPoints_Main.FloatValue;
		fBaiscFinishPoint = gCV_BasicFinishPoints_Main.FloatValue;
		fExtraFinishPoint = tier * Pow(max(0.0, tier-4.0), 2.0) * fBaiscFinishPoint;
	}
	else 
	{
		fMaxRankPoint = gCV_MaxRankPoints_Stage.FloatValue;
		fBaiscFinishPoint = gCV_BasicFinishPoints_Stage.FloatValue == 0.0 ? tier : gCV_BasicFinishPoints_Main.FloatValue;
	}

	float fRankPoint = fMaxRankPoint / float(rank);
	float fFinishPoint = fBaiscFinishPoint * tier;

	float fTotalPoint = (fRankPoint + fFinishPoint + fExtraFinishPoint) * stylemultiplier;

	return fTotalPoint;
}

public void SQL_DeleteMap_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings deletemap) SQL query failed. Reason: %s", error);

		return;
	}

	if(view_as<bool>(data))
	{
		gI_Tier = gCV_DefaultTier.IntValue;

		UpdateAllPoints(true);
	}
}

stock float max(float a, float b)
{
	return a > b ? a:b;
}

#if USE_SHMAPTIERS
stock void GetMapInfoFromSurfHeaven(const char[] map)
{
	char sUrl[256];
	FormatEx(sUrl, sizeof(sUrl), "%s%s", SH_MAPINFO_URL, map);
	HTTPRequest request = new HTTPRequest(sUrl);
	request.Timeout = 3600;
	request.Get(GetMapInfoFromSurfHeaven_Callback);
}

public void GetMapInfoFromSurfHeaven_Callback(HTTPResponse response, any data, const char[] error)
{
	if(response.Status != HTTPStatus_OK)
	{
		LogError("( Rankings GetMapInfo ) Fail to fetch map info from surf heaven. Reason: %s", error);
		return;
	}

	char sResult[1024];
	response.Data.ToString(sResult, sizeof(sResult));

	if(sResult[0] == '\0')
	{
		return;
	}

	JSONArray array = view_as<JSONArray>(response.Data);

	if(array.Length < 1)
	{
		delete array;
		return;
	}

	JSONObject info = view_as<JSONObject>(array.Get(0));

	gI_Tier = info.GetInt("tier");

	delete info;
	delete array;

	gA_MapTiers.SetValue(gS_Map, gI_Tier);

	Call_StartForward(gH_Forwards_OnTierAssigned);
	Call_PushString(gS_Map);
	Call_PushCell(gI_Tier);
	Call_Finish();

	Shavit_PrintToChatAll("%T", "SetTier", LANG_SERVER, gS_ChatStrings.sVariable2, gI_Tier, gS_ChatStrings.sText);

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery), "REPLACE INTO %smaptiers (map, tier, maxvelocity) VALUES ('%s', %d, %f);", gS_MySQLPrefix, gS_Map, gI_Tier, gCV_DefaultMaxVelocity.FloatValue);
	QueryLog(gH_SQL, SQL_SetMapTier_Callback, sQuery, 0, DBPrio_High);

	Shavit_LogMessage("[Server] - set tier of `%s` to %d", gS_Map, gI_Tier);
}
#endif