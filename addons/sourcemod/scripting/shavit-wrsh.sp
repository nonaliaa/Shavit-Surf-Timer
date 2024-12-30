#include <sourcemod>
#include <convar_class>
#include <shavit/core>
#include <shavit/zones>
#include <shavit/wr>
#include <shavit/wrsh>
#include <ripext>

Convar gCV_MaxFetchingTime;
Convar gCV_MaxRankingTime;
Convar gCV_MaxRequest;
Convar gCV_RetryInterval;
Convar gCV_RankingCoolDown;
// Convar gCV_RefreshRecordInterval;

wrinfo_t gA_MapWorldRecord[TRACKS_SIZE];
wrinfo_t gA_StageWorldRecord[MAX_STAGES];

chatstrings_t gS_ChatStrings;
stylestrings_t gS_StyleStrings[STYLE_LIMIT];

char gS_Map[PLATFORM_MAX_PATH];
char gS_PreviousMap[PLATFORM_MAX_PATH];

int gI_RequestTimes;
bool gB_Fetching = false;
bool gB_Stop = false;
bool gB_MapWRCached = false;
bool gB_StageWRCached = false;
bool gB_CacheFail = false;

bool gB_Timer;

float gF_ReadyTime[MAXPLAYERS + 1];
bool gB_CoolDown[MAXPLAYERS + 1];
Handle gH_CoolDown[MAXPLAYERS + 1];

Handle gH_FetchTimer;

bool gB_Late;

public Plugin myinfo =
{
	name = "[shavit-surf] WR-SH",
	author = "KikI",
	description = "Fetching top records of current maps from Surf Heaven.",
	version = "0.0.1",
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	//natives
	CreateNative("Shavit_GetSHMapRecordTime", Native_GetSHMapRecordTime);
	CreateNative("Shavit_GetSHMapRecordName", Native_GetSHMapRecordName);
	CreateNative("Shavit_GetSHStageRecordTime", Native_GetSHStageRecordTime);
	CreateNative("Shavit_GetSHStageRecordName", Native_GetSHStageRecordName);

	RegPluginLibrary("shavit-wrsh");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("shavit-common.phrases");

	RegConsoleCmd("sm_shmaprank", Command_SHMapRank, "Print client's rank of map time in SurfHeaven");
	RegConsoleCmd("sm_shrank", Command_SHMapRank, "Print client's rank of map time in SurfHeaven");

	RegConsoleCmd("sm_shstagerank", Command_SHStageRank, "Print client's rank of stage time in SurfHeaven");
	RegConsoleCmd("sm_shsrank", Command_SHStageRank, "Print client's rank of stage time in SurfHeaven");

	RegConsoleCmd("sm_shmaptop", Command_SHMapTop, "Display top records of map in SurfHeaven");
	RegConsoleCmd("sm_shtop", Command_SHMapTop, "Display top records of map in SurfHeaven");
	RegConsoleCmd("sm_shwr", Command_SHMapTop, "Display top records of map in SurfHeaven");

	RegConsoleCmd("sm_shstagetop", Command_SHStageTop, "Display top stage records of map in SurfHeaven");
	RegConsoleCmd("sm_shstop", Command_SHStageTop, "Display top stage records of map in SurfHeaven");
	RegConsoleCmd("sm_shcptop", Command_SHStageTop, "Display top stage records of map in SurfHeaven");
	RegConsoleCmd("sm_shcpwr", Command_SHStageTop, "Display top stage records of map in SurfHeaven");
	RegConsoleCmd("sm_shwrcp", Command_SHStageTop, "Display top stage records of map in SurfHeaven");

	RegAdminCmd("sm_reloadshrecord", Command_ReloadSHRecord, ADMFLAG_RCON, "Reload SH record.")
	RegAdminCmd("sm_stopfetchingrecord", Command_StopFetchingSHRecord, ADMFLAG_RCON, "Stop fetching records from surfheaven.")

	gCV_MaxFetchingTime = new Convar("shavit_wrsh_maxfetchingtime", "60.0", "Maximum time to fetching records from SurfHeaven.", 0, true, 10.0, false, 0.0);
	gCV_MaxRankingTime = new Convar("shavit_wrsh_maxrankingtime", "30.0", "Maximum time to ranking player's time from SurfHeaven.", 0, true, 10.0, false, 0.0);
	gCV_MaxRequest = new Convar("shavit_wrsh_maxrequest", "10", "Maximum number of requests with no response sent.", 0, true, 1.0, false, 0.0);
	gCV_RetryInterval = new Convar("shavit_wrsh_retryinterval", "10.0", "The interval between sending requests if records are not cached.", 0, true, 10.0, false, 0.0);
	gCV_RankingCoolDown = new Convar("shavit_wrsh_rankingcooldown", "30.0", "The interval (in seconds) allow client use rank command again.", 0, true, 30.0, false, 0.0);

	// gCV_RefreshRecordInterval = new Convar("shavit_wrsh_refreshinterval", "30", "How often (in minutes) should refresh records.", 0, true, -1, false, 0);
	Convar.AutoExecConfig();

	if(gB_Late)
	{
		Shavit_OnChatConfigLoaded();
		Shavit_OnStyleConfigLoaded(Shavit_GetStyleCount());
		OnMapStart();

		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void Shavit_OnChatConfigLoaded()
{
	Shavit_GetChatStringsStruct(gS_ChatStrings);
}

public void Shavit_OnStyleConfigLoaded(int styles)
{
	for(int i = 0; i < styles; i++)
	{
		Shavit_GetStyleStringsStruct(i, gS_StyleStrings[i]);
	}
}

// commands
public Action Command_ReloadSHRecord(int client, int args)
{
	OpenReloadSHReocrdMenu(client);

	return Plugin_Handled;
}

public Action Command_StopFetchingSHRecord(int client, int args)
{
	if(gB_MapWRCached && gB_StageWRCached)
	{
		return Plugin_Continue;
	}

	Shavit_LogMessage("%L - Stop server fetching SH records.", client);
	gB_Stop = true;

	return Plugin_Handled;
}

public Action Command_SHStageTop(int client, int args)
{
	BuildSHStageTopMenu(client, -1, 0);
	return Plugin_Handled;
}

public Action Command_SHMapTop(int client, int args)
{
	BuildSHMapTopMenu(client, -1, 0);
	return Plugin_Handled;
}

public Action Command_SHMapRank(int client, int args)
{
	if(gB_CoolDown[client])
	{
		Shavit_PrintToChat(client, "You just ranking few seconds ago, please wait %s%.1f %sseconds before using this command.",
		gS_ChatStrings.sVariable2, gF_ReadyTime[client] - GetEngineTime(), gS_ChatStrings.sText);
		return Plugin_Handled;
	}
	
	if(gB_Fetching)
	{
		Shavit_PrintToChat(client, "Plugin is fetching data currently, please try again later.");
		return Plugin_Handled;
    }

	int track = Shavit_GetClientTrack(client);
	float time = Shavit_GetClientPB(client, Shavit_GetBhopStyle(client), track);

	if(gB_Stop || (gA_MapWorldRecord[track].iRankCount == 0 && gB_MapWRCached))
	{
		Shavit_PrintToChat(client, "There are no records in SurfHeaven.");
		return Plugin_Handled;
	}

	if(time > 0.0)
	{
		if(IsValidHandle(gH_FetchTimer))
		{
			delete gH_FetchTimer;
		}

		gH_FetchTimer = CreateTimer(gCV_MaxRankingTime.FloatValue, Timer_Ranking, client, TIMER_FLAG_NO_MAPCHANGE);
		Shavit_PrintToChat(client, "Start ranking from SurfHeaven, please wait.");
		GetSHSMapRank(client, time, track);     
	}
	else
	{
		char sTrack[32];
		GetTrackName(client, track, sTrack, 32);
		Shavit_PrintToChat(client, "You have no records in %s.", sTrack);
	}

	return Plugin_Handled;
}

public Action Command_SHStageRank(int client, int args)
{
	if(gB_CoolDown[client])
	{
		Shavit_PrintToChat(client, "You just ranking few seconds ago, please wait %s%.1f%s seconds before using this command.",
		gS_ChatStrings.sVariable2, gF_ReadyTime[client] - GetEngineTime(), gS_ChatStrings.sText);
		return Plugin_Handled;
	}

	if(gB_Fetching)
	{
        Shavit_PrintToChat(client, "Plugin is fetching data currently, please try again later.");
        return Plugin_Handled;
    }

	int stage;

	if(args > 0)
	{
		char sArg[8];
		GetCmdArg(1, sArg, 8);
		stage = StringToInt(sArg);
	}
	else
	{
		stage = Shavit_GetClientLastStage(client);      
	}

	if(gB_Stop || gA_StageWorldRecord[stage].iRankCount == 0 && gB_StageWRCached)
	{
		Shavit_PrintToChat(client, "There are no records in SurfHeaven.");
		return Plugin_Handled;
	}

	float time = Shavit_GetClientStagePB(client, Shavit_GetBhopStyle(client), Shavit_GetClientLastStage(client));

	if(time > 0.0)
	{
		if(IsValidHandle(gH_FetchTimer))
		{
			delete gH_FetchTimer;
		}

		gH_FetchTimer = CreateTimer(gCV_MaxRankingTime.FloatValue, Timer_Ranking, client, TIMER_FLAG_NO_MAPCHANGE);
		Shavit_PrintToChat(client, "Start ranking from SurfHeaven, please wait.");
		GetSHStageRank(client, time, stage);     
	}
	else
	{
		Shavit_PrintToChat(client, "You have no records in Stage %d.", stage);
	}

	return Plugin_Handled;
}
//////////////////////////

public Action Timer_CacheWorldRecord(Handle timer)
{
	gB_Timer = true;
	if(!gB_Fetching)
	{
		if(!gB_MapWRCached)
		{
			CacheWorldRecord(gS_Map);
		}
		else if(!gB_StageWRCached)
		{
			CacheStageWorldRecord(gS_Map);
		}

		gI_RequestTimes = gI_RequestTimes + 1;
	}

	if(gB_Stop || gI_RequestTimes > gCV_MaxRequest.IntValue || (gB_MapWRCached && gB_StageWRCached))
	{
		gB_CacheFail = !(gB_MapWRCached && gB_StageWRCached);
		gB_Timer = false;
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public void OnMapStart()
{
	GetLowercaseMapName(gS_Map);
	gB_Fetching = false;
	gI_RequestTimes = 0;
	
	if (!StrEqual(gS_Map, gS_PreviousMap))
	{
		gB_Stop = false;
		ResetWRCache();
		CreateTimer(gCV_RetryInterval.FloatValue, Timer_CacheWorldRecord, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void OnMapEnd()
{
	gS_PreviousMap = gS_Map;
}

public void OnClientPutInServer(int client)
{
	float cd = gF_ReadyTime[client] - GetEngineTime();
	gB_CoolDown[client] = cd > 0.1;

	if(IsValidHandle(gH_CoolDown[client]))
	{
		delete gH_CoolDown[client];
	}

	if(gB_CoolDown[client])
	{
		CreateTimer(cd, Timer_CoolDown, client, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void ResetWRCache()
{
	wrinfo_t empty_cache;
	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		gA_MapWorldRecord[i] = empty_cache;
	}

	for(int j = 1; j < MAX_STAGES; j++)
	{
		gA_StageWorldRecord[j] = empty_cache;
	}

	gB_MapWRCached = false;
	gB_StageWRCached = false;
	gB_CacheFail = false;
}

// cache stuffs on map start
public void CacheStageWorldRecord(const char[] map)
{
	if(gB_Stop)
	{
		return;
	}

	if(Shavit_GetStageCount(Track_Main) < 2)
	{
		gB_Fetching = false;
		gB_StageWRCached = true;
		return;
	}

	char sUrl[256];
	FormatEx(sUrl, sizeof(sUrl), "%s%s", SH_STAGERECORD_URL, map);
	gB_Fetching = true;

	if(IsValidHandle(gH_FetchTimer))
	{
		delete gH_FetchTimer;
	}

	gH_FetchTimer = CreateTimer(gCV_MaxFetchingTime.FloatValue, Timer_Fetching, true, TIMER_FLAG_NO_MAPCHANGE);

	HTTPRequest request = new HTTPRequest(sUrl);
	request.Timeout = 60; // in seconds
	request.Get(CacheStageWorldRecord_Callback);
}

public void CacheWorldRecord(const char[] map)
{
	if(gB_Stop)
	{
		return;
	}

	char sUrl[256];
	FormatEx(sUrl, sizeof(sUrl), "%s%s", SH_MAPRECORD_URL, map);
	gB_Fetching = true;

	if(IsValidHandle(gH_FetchTimer))
	{
		delete gH_FetchTimer;
	}

	gH_FetchTimer = CreateTimer(gCV_MaxFetchingTime.FloatValue, Timer_Fetching, false, TIMER_FLAG_NO_MAPCHANGE);

	HTTPRequest request = new HTTPRequest(sUrl);
	request.Timeout = 60; // in seconds
	request.Get(CacheMapWorldRecord_Callback);
}

public void CacheMapWorldRecord_Callback(HTTPResponse response, any data, const char[] error)
{
	if(response.Status != HTTPStatus_OK)
	{
		LogError("Fail to fetch map records from surf heaven. Reason: %s", error);
		gB_Fetching = false;
		return;
	}

	JSONArray array = view_as<JSONArray>(response.Data);

	if(array.Length < 1 || gB_Stop)
	{
		gB_Fetching = false;
		gB_MapWRCached = true;
		gB_StageWRCached = true;
		delete array;

		if(IsValidHandle(gH_FetchTimer))
		{
			delete gH_FetchTimer;
		}
		return;
	}

	char sMap[PLATFORM_MAX_PATH];
	JSONObject temp = view_as<JSONObject>(array.Get(0));
	temp.GetString("map", sMap, sizeof(sMap));

	delete temp;

	if(!StrEqual(sMap, gS_Map, true))
	{
		delete array;
		gB_Fetching = false;
		return;
	}

	for (int i = 0; i < array.Length; i++)
	{
		JSONObject record = view_as<JSONObject>(array.Get(i))
		int iRank = record.GetInt("rank");
		int iTrack = record.GetInt("track");

		gA_MapWorldRecord[iTrack].iRankCount++;

		if (iRank == 1)
		{
			if(iTrack <= TRACKS_SIZE)
			{
				gA_MapWorldRecord[iTrack].fTime = record.GetFloat("time");
				
				if(gA_MapWorldRecord[iTrack].fTime == 0.0)
				{
					gA_MapWorldRecord[iTrack].fTime = float(record.GetInt("time"));
				}

				record.GetString("name", gA_MapWorldRecord[iTrack].sName, sizeof(wrinfo_t::sName));

				char sDate[32];
				record.GetString("date", sDate, sizeof(sDate));

				char exploded[2][16];
				ExplodeString(sDate, "T", exploded, 2, 16);
				gA_MapWorldRecord[iTrack].sDate = exploded[0];
			}
		}

		delete record;
	}

	delete array;

	if(IsValidHandle(gH_FetchTimer))
	{
		delete gH_FetchTimer;
	}

	gB_MapWRCached = true;

	CacheStageWorldRecord(gS_Map);
}

public void CacheStageWorldRecord_Callback(HTTPResponse response, any data, const char[] error)
{
	if(response.Status != HTTPStatus_OK)
	{
		LogError("Fail to fetch stage records from surf heaven. Reason: %s", error);
		gB_Fetching = false;
		return;
	}

	JSONArray array = view_as<JSONArray>(response.Data);

	if(array.Length < 1 || gB_Stop)
	{
		gB_Fetching = false;
		gB_StageWRCached = true;
		delete array;

		if(IsValidHandle(gH_FetchTimer))
		{
			delete gH_FetchTimer;
		}
		return;
	}

	char sMap[PLATFORM_MAX_PATH];
	JSONObject temp = view_as<JSONObject>(array.Get(0));
	temp.GetString("map", sMap, sizeof(sMap));

	delete temp;

	if(!StrEqual(sMap, gS_Map, true))
	{
		delete array;
		gB_Fetching = false;
		return;
	}

	for (int i = 0; i < array.Length; i++)
	{
		JSONObject record = view_as<JSONObject>(array.Get(i))
		int iRank = record.GetInt("rank");
		int iStage = record.GetInt("stage");

		gA_StageWorldRecord[iStage].iRankCount++;

		if (iRank == 1)
		{
			if(iStage <= MAX_STAGES)
			{
				gA_StageWorldRecord[iStage].fTime = record.GetFloat("time");

				if(gA_StageWorldRecord[iStage].fTime == 0.0)
				{
					gA_StageWorldRecord[iStage].fTime = float(record.GetInt("time"));
				}

				record.GetString("name", gA_StageWorldRecord[iStage].sName, sizeof(wrinfo_t::sName));

				char sDate[32];
				record.GetString("date", sDate, sizeof(sDate));

				char exploded[2][16];
				ExplodeString(sDate, "T", exploded, 2, 16);
				gA_StageWorldRecord[iStage].sDate = exploded[0];
			}
		}

		delete record;
	}

	delete array;

	gB_StageWRCached = true;

	if(IsValidHandle(gH_FetchTimer))
	{
		delete gH_FetchTimer;
	}

	gB_Fetching = false;
}
////////////////////////////

// natives
public int Native_GetSHMapRecordTime(Handle handler, int numParams)
{
	int iTrack = GetNativeCell(1);

	if(iTrack < 0 || iTrack > TRACKS_SIZE)
	{
		return view_as<int>(0.0);
	}
    
	if(gB_MapWRCached)
	{
		return view_as<int>(gA_MapWorldRecord[iTrack].fTime);
	}
	else if(!gB_CacheFail)
	{
		return view_as<int>(-1.0);
	}

	return view_as<int>(0.0);
}

public int Native_GetSHMapRecordName(Handle handler, int numParams)
{
	int iTrack = GetNativeCell(1);

	if(iTrack < 0 || iTrack > TRACKS_SIZE)
	{
		SetNativeString(2, "None", GetNativeCell(3));
		return 0;
	}

	if(gB_MapWRCached)
	{
		SetNativeString(2, gA_MapWorldRecord[iTrack].sName, GetNativeCell(3));
	}
	else if(!gB_CacheFail)
	{
		SetNativeString(2, "Loading...", GetNativeCell(3));
	}
	else
	{
		SetNativeString(2, "None", GetNativeCell(3));
	}

	return 0;
}

public int Native_GetSHStageRecordTime(Handle handler, int numParams)
{
	int iStage = GetNativeCell(1);

	if(iStage < 1 || iStage > MAX_STAGES)
	{
		return view_as<int>(0.0);
	}
    
	if(gB_StageWRCached)
	{
		return view_as<int>(gA_StageWorldRecord[iStage].fTime)        
	}
	else if(!gB_CacheFail)
	{
		return view_as<int>(-1.0);
	}

	return view_as<int>(0.0);
}

public int Native_GetSHStageRecordName(Handle handler, int numParams)
{
	int iStage = GetNativeCell(1);

	if(iStage < 1 || iStage > MAX_STAGES)
	{
		SetNativeString(2, "None", GetNativeCell(3));
		return 0;
    }

	if(gB_StageWRCached)
	{
		SetNativeString(2, gA_StageWorldRecord[iStage].sName, GetNativeCell(3));
	}
	else if(!gB_CacheFail)
	{
		SetNativeString(2, "Loading...", GetNativeCell(3));
	}
	else
	{
		SetNativeString(2, "None", GetNativeCell(3));
	}

	return 0;
}
////////////////////

// rank stuffs
public void GetSHSMapRank(int client, float time, int track)
{
	char sUrl[256];
	FormatEx(sUrl, sizeof(sUrl), "%s%s", SH_MAPRECORD_URL, gS_Map);

	gB_Fetching = true;

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(time);
	pack.WriteCell(track);

	HTTPRequest request = new HTTPRequest(sUrl);
	request.Timeout = 60; 
	request.Get(GetSHMapRank_Callback, pack);
}

public void GetSHMapRank_Callback(HTTPResponse response, DataPack pack, const char[] error)
{
	pack.Reset();
	int client = GetClientFromSerial(pack.ReadCell());
	float time = pack.ReadCell();
	int track = pack.ReadCell();
	delete pack;

	if(response.Status != HTTPStatus_OK)
	{
		gB_Fetching = false;
		Shavit_PrintToChat(client, "Failed to retrieve ranking from SurfHeaven.");

		return;
	}

	JSONArray array = view_as<JSONArray>(response.Data);

	int maxrank = array.Length;
	int minrank = 1;

	int rank;

	if (time < gA_MapWorldRecord[track].fTime)
	{
		CallOnFinishRanking(client, track, 0, 1, time);
		delete array;
		return;
	}

	for (int i = 0; i < array.Length; i++)
	{
		JSONObject record = view_as<JSONObject>(array.Get(i))
		int iTrack = record.GetInt("track");
		
		if (track == iTrack)
		{
			float fTime = record.GetFloat("time");
			int iRank = record.GetInt("rank");

			if (iRank > maxrank || iRank < minrank)
			{
				delete record;
				continue;
			}
			else if(maxrank - 1 == minrank)
			{
				CallOnFinishRanking(client, track, 0, maxrank, time);
				delete record;
				delete array;
				return;
			}

			if(fTime < time)
			{
				minrank = iRank;
			}
			else if(fTime > time)
			{
				maxrank = iRank;
			}
			else if(time == fTime)
			{
				CallOnFinishRanking(client, track, 0, iRank, time);
				delete record;
				delete array;
				return;
			}
		}

		delete record;
	}

	rank = minrank + 1;
	CallOnFinishRanking(client, track, 0, rank, time);
	delete array;
}

public void GetSHStageRank(int client, float time, int stage)
{
	char sUrl[256];
	FormatEx(sUrl, sizeof(sUrl), "%s%s", SH_STAGERECORD_URL, gS_Map);

	gB_Fetching = true;

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(time);
	pack.WriteCell(stage);

	HTTPRequest request = new HTTPRequest(sUrl);
	request.Timeout = 60;
	request.Get(GetSHStageRank_Callback, pack);
}

public void GetSHStageRank_Callback(HTTPResponse response, DataPack pack, const char[] error)
{
	pack.Reset();
	int client = GetClientFromSerial(pack.ReadCell());
	float time = pack.ReadCell();
	int stage = pack.ReadCell();
	delete pack;

	if(response.Status != HTTPStatus_OK)
	{
		gB_Fetching = false;
		Shavit_PrintToChat(client, "Failed to retrieve rank from SurfHeaven.");

		return;
	}

	JSONArray array = view_as<JSONArray>(response.Data);

	int maxrank = array.Length;
	int minrank = 1;

	int rank;

	if (time < gA_StageWorldRecord[stage].fTime)
	{
		CallOnFinishRanking(client, Track_Main, stage, 1, time);
		delete array;
	}

	for (int i = 0; i < array.Length; i++)
	{
		JSONObject record = view_as<JSONObject>(array.Get(i))
		int iStage = record.GetInt("stage");
		
		if (stage == iStage)
		{
			float fTime = record.GetFloat("time");
			int iRank = record.GetInt("rank");

			if (iRank > maxrank || iRank < minrank)
			{
				delete record;
				continue;
			}
			else if(maxrank - 1 == minrank)
			{
				CallOnFinishRanking(client, Track_Main, stage, maxrank, time);
				delete record;
				delete array;
				return;
			}

			if(fTime < time)
			{
				minrank = iRank;
			}
			else if(fTime > time)
			{
				maxrank = iRank;
			}
			else if(time == fTime)
			{
				CallOnFinishRanking(client, Track_Main, stage, iRank, time);
				delete record;
				delete array;
				return;
			}
		}

		delete record;
	}

	rank = minrank + 1;
	CallOnFinishRanking(client, Track_Main, stage, rank, time);
	delete array;
}

public void CallOnFinishRanking(int client, int track, int stage, int rank, float time)
{
	gB_Fetching = false;
	gB_CoolDown[client] = true;

	if(IsValidHandle(gH_FetchTimer))
	{
		delete gH_FetchTimer;
	}

	if (IsValidHandle(gH_CoolDown[client]))
	{
		delete gH_CoolDown[client];			
	}

	gF_ReadyTime[client] = gCV_RankingCoolDown.FloatValue + GetEngineTime();
	gH_CoolDown[client] = CreateTimer(gCV_RankingCoolDown.FloatValue, Timer_CoolDown, client, TIMER_FLAG_NO_MAPCHANGE);

	char sTrack[32];
	int iRankCount;

	if(track == 0 && stage > 0)
	{
		iRankCount = gA_StageWorldRecord[stage].iRankCount;
		FormatEx(sTrack, 32, "Stage %d", stage);
	}
	else
	{
		iRankCount = gA_MapWorldRecord[track].iRankCount;
		GetTrackName(client, track, sTrack, 32);
	}

	char sTime[16];
	FormatSeconds(time, sTime, 16, true);

	Shavit_PrintToChat(client, "You ranked %s#%d%s (%s%d%s) with a time of %s%s%s %s[%s]%s in SurfHeaven.", 
		gS_ChatStrings.sVariable, rank, gS_ChatStrings.sText, 
		gS_ChatStrings.sVariable, iRankCount + 1, gS_ChatStrings.sText, 
		gS_ChatStrings.sVariable2, sTime, gS_ChatStrings.sText, 
		gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);
}

public Action Timer_Fetching(Handle timer, bool stage)
{
	gB_Fetching = false;
	Shavit_PrintToChatAll("Fetching SH %s record falied.", stage ? "stage":"map");

	return Plugin_Stop;
}

public Action Timer_Ranking(Handle timer, int client)
{
	gB_Fetching = false;
	Shavit_PrintToChat(client, "Ranking time out.");

	return Plugin_Stop;
}

public Action Timer_CoolDown(Handle timer, int client)
{
	gH_CoolDown[client] = null;
	gB_CoolDown[client] = false;

	return Plugin_Stop;
}

// sh menu stuff
public void BuildSHMapTopMenu(int client, int track, int item)
{
	Menu menu = new Menu(MenuHandler_SHMapTop);

	if(gB_MapWRCached)
	{
		menu.SetTitle("Top records from SurfHeaven\nMap: %s\n ", gS_Map);

		for (int i = 0; i < TRACKS_SIZE; i++)
		{
			char sInfo[4];
			IntToString(i, sInfo, 4);

			bool hasRecord = (gA_MapWorldRecord[i].iRankCount > 0 && gB_MapWRCached)

			char sTrack[32];
			GetTrackName(client, i, sTrack, 32);

			char sMenu[256];
			if (hasRecord)
			{
				char sTime[16];
				FormatSeconds(gA_MapWorldRecord[i].fTime, sTime, 16);
				FormatEx(sMenu, sizeof(sMenu), "%s - %s", sTrack, sTime);
				if (i == track)
				{
					int iStyle = Shavit_GetBhopStyle(client);
					char sTimeDiff[32];
					FormatEx(sTimeDiff, 32, "None");
					char sDiff[16];

					if(Shavit_GetWorldRecord(iStyle, i) > 0.0)
					{
						float fDiffSR = Shavit_GetWorldRecord(iStyle, i) - gA_MapWorldRecord[i].fTime;
						FormatSeconds(fDiffSR, sDiff, 16);
						FormatEx(sTimeDiff, 32, "SR %s%s", fDiffSR > 0 ? "+":"", sDiff);
					}

					if(Shavit_GetClientPB(client, iStyle, i) > 0.0)
					{
						float fDiffPB = Shavit_GetClientPB(client, iStyle, i) - gA_MapWorldRecord[i].fTime;
						FormatSeconds(fDiffPB, sDiff, 16);
						FormatEx(sTimeDiff, 32, "%s | PB %s%s", sTimeDiff, fDiffPB > 0 ? "+":"", sDiff);
					}

					FormatEx(sMenu, sizeof(sMenu), "%s\n  || Gap: %s (%s)\n  || Runner: %s\n  || Date: %s\n  || Total records: %d", 
					sMenu, sTimeDiff, gS_StyleStrings[iStyle], gA_MapWorldRecord[i].sName, gA_MapWorldRecord[i].sDate, gA_MapWorldRecord[i].iRankCount);
				}
			}
			else
			{
				FormatEx(sMenu, sizeof(sMenu), "%s - No record", sTrack);
			}

			menu.AddItem(sInfo, sMenu, (hasRecord ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED));
		}

		if(menu.ItemCount == 0)
		{
			menu.AddItem("-1", "No records found.", ITEMDRAW_DISABLED);
		}
	}
	else if(!gB_CacheFail)
	{
		menu.SetTitle("Top records from SurfHeaven\nMap: %s\n \nLoading...\n ", gS_Map);
		menu.AddItem("-1", "Refresh");
	}
	else
	{
		menu.SetTitle("Top records from SurfHeaven\nMap: %s\n ", gS_Map);
		menu.AddItem("-1", "Fail to fetch records from SurfHeaven");
	}

	menu.DisplayAt(client, MENU_TIME_FOREVER, item);
}

public int MenuHandler_SHMapTop(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[4];
		menu.GetItem(param2, sInfo, 4);

		BuildSHMapTopMenu(param1, StringToInt(sInfo), GetMenuSelectionPosition());
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void BuildSHStageTopMenu(int client, int stage, int item)
{
	Menu menu = new Menu(MenuHandler_SHStageTop);

	if(gB_StageWRCached)
	{
		menu.SetTitle("Top stage records from SurfHeaven\nMap: %s\n ", gS_Map);

		for (int i = 0; i < MAX_STAGES; i++)
		{
			char sInfo[8];
			IntToString(i, sInfo, 8);

			bool hasRecord = (gA_StageWorldRecord[i].iRankCount > 0 && gB_StageWRCached)

			if(!hasRecord)
			{
				continue;
			}

			char sMenu[256];

			char sTime[16];
			FormatSeconds(gA_StageWorldRecord[i].fTime, sTime, 16);
			FormatEx(sMenu, sizeof(sMenu), "Stage %d - %s", i, sTime);
			if (i == stage)
			{
				int iStyle = Shavit_GetBhopStyle(client);
				char sTimeDiff[32];
				FormatEx(sTimeDiff, 32, "None");
				char sDiff[16];

				if(Shavit_GetStageWorldRecord(iStyle, i) > 0.0)
				{
					float fDiffSR = Shavit_GetStageWorldRecord(iStyle, i) - gA_StageWorldRecord[i].fTime;
					FormatSeconds(fDiffSR, sDiff, 16);
					FormatEx(sTimeDiff, 32, "SR %s%s", fDiffSR > 0 ? "+":"", sDiff);
				}

				if(Shavit_GetClientStagePB(client, iStyle, i) > 0.0)
				{
					float fDiffPB = Shavit_GetClientStagePB(client, iStyle, i) - gA_StageWorldRecord[i].fTime;
					FormatSeconds(fDiffPB, sDiff, 16);
					FormatEx(sTimeDiff, 32, "%s | PB %s%s", sTimeDiff, fDiffPB > 0 ? "+":"", sDiff);
				}

				FormatEx(sMenu, sizeof(sMenu), "%s\n  || Gap: %s (%s)\n  || Runner: %s\n  || Date: %s\n  || Total records: %d",
				sMenu, sTimeDiff, gS_StyleStrings[iStyle], gA_StageWorldRecord[i].sName, gA_StageWorldRecord[i].sDate, gA_StageWorldRecord[i].iRankCount);
			}

			menu.AddItem(sInfo, sMenu, (hasRecord ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED));
		}

		if(menu.ItemCount == 0)
		{
			menu.AddItem("-1", "No records found.", ITEMDRAW_DISABLED);
		}
	}
	else if(!gB_CacheFail)
	{
		menu.SetTitle("Top stage records from SurfHeaven\nMap: %s\nLoading... \n ", gS_Map);
		menu.AddItem("-1", "Refresh");
	}
	else
	{
		menu.SetTitle("Top stage records from SurfHeaven\nMap: %s\n ", gS_Map);
		menu.AddItem("-1", "Fail to fetch records from SurfHeaven", ITEMDRAW_DISABLED);
	}

	menu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int MenuHandler_SHStageTop(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		int iMenuPos = GetMenuSelectionPosition();

		char sInfo[4];
		menu.GetItem(param2, sInfo, 4);

		BuildSHStageTopMenu(param1, StringToInt(sInfo), iMenuPos);
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OpenReloadSHReocrdMenu(int client)
{
	Menu menu = new Menu(MenuHandler_ReloadSHRecord);
	char sStatus[16];
	
	if(gB_Stop)
	{
		FormatEx(sStatus, 16, "Forcibly Stop Fetching");
	}
	else if(gB_Fetching)
	{
		FormatEx(sStatus, 16, "Fetching");
	}
	else if(gB_CacheFail)
	{
		FormatEx(sStatus, 16, "Fail");
	}
	else
	{
		FormatEx(sStatus, 16, "None");
	}

	menu.SetTitle(
	"Reload Records Option Menu\nWarning: Use it carefully when RAISED a JSON error!\n \n"...
	"====== Plugin Info ====== \n"...
	"    Status: %s\n"...
	"    Timer: %s\n"...
	"    Request Sent: %d (%d)\n"...
	"    Stage Record Cached: %s\n"...
	"    Map Record Cached: %s\n====================\n ",
	sStatus, gB_Timer ? "Running":"Stopped", gI_RequestTimes, gCV_MaxRequest.IntValue, gB_MapWRCached ? "True":"False", gB_StageWRCached ? "True":"False");

	menu.AddItem("refresh", "Refresh Status\n ");
	if(gB_Stop)
	{
		menu.AddItem("resume", "Resume fetching");		
	}
	else
	{
		menu.AddItem("stop", "Forcibly Stop fetching");		
	}
	menu.AddItem("reset", "Reset Record Cache");
	menu.AddItem("unfetching", "Set Fetching to false");
	menu.AddItem("reload", "Reload Records", gB_Fetching ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	menu.AddItem("restart", "Restart Timer", gB_Timer ? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);

	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_ReloadSHRecord(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "refresh"))
		{
			OpenReloadSHReocrdMenu(param1);
		}
		else if(StrEqual(sInfo, "resume"))
		{
			Shavit_LogMessage("%L - Restart server fetching SH records.", param1);
			gB_Stop = false;

			OpenReloadSHReocrdMenu(param1);
		}
		else if(StrEqual(sInfo, "stop"))
		{
			Shavit_LogMessage("%L - Stop server fetching SH records.", param1);
			gB_Stop = true;

			OpenReloadSHReocrdMenu(param1);
		}
		else if(StrEqual(sInfo, "reset"))
		{
			Shavit_LogMessage("%L - Reseted SH Record cache.", param1);
			gB_Fetching = false;
			ResetWRCache();
			OpenReloadSHReocrdMenu(param1);
		}
		else if(StrEqual(sInfo, "unfetching"))
		{
			Shavit_LogMessage("%L - Reseted Plugin status.", param1);
			gB_Fetching = false;
			
			OpenReloadSHReocrdMenu(param1);
		}
		else if(StrEqual(sInfo, "reload"))
		{
			Shavit_LogMessage("%L - Reloaded SH Record cache.", param1);
			CacheWorldRecord(gS_Map);
			OpenReloadSHReocrdMenu(param1);
		}
		else if(StrEqual(sInfo, "restart"))
		{
			Shavit_LogMessage("%L - Restarted cache Timer.", param1);
			gI_RequestTimes = 1;
			CreateTimer(gCV_RetryInterval.FloatValue, Timer_CacheWorldRecord, 0, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
			OpenReloadSHReocrdMenu(param1);
		}
	}
	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}