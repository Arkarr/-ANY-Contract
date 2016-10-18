#include <sourcemod>
#include <sdktools>
#include <multicolors>
#include <sdkhooks>
#undef REQUIRE_PLUGIN
#include <zephyrus_store>
#include <smrpg>
#include <smstore/store/store-backend>
#undef REQUIRE_EXTENSIONS
#include <tf2_stocks>
#include <cstrike>

//Plugin Info
#define PLUGIN_TAG						"{green}[{red}Contract{green}]{default}"
#define PLUGIN_NAME						"[ANY] Contract"
#define PLUGIN_AUTHOR 					"Arkarr"
#define PLUGIN_VERSION 					"1.5"
#define PLUGIN_DESCRIPTION 				"Assign cotnract to player and let them a certain period of time to do it to earn extra credits."
//KeyValue fields
#define FIELD_CONTRACT_NAME 			"Contract Name"
#define FIELD_CONTRACT_ACTION			"Contract Type"
#define FIELD_CONTRACT_OBJECTIVE		"Contract Objective"
#define FIELD_CONTRACT_CHANCES			"Contract Chances"
#define FIELD_CONTRACT_REWARD			"Contract Reward"
#define FIELD_CONTRACT_WEAPON			"Contract Weapon"
//Database queries
#define QUERY_INIT_DATABASE				"CREATE TABLE IF NOT EXISTS `contracts` (`steamid` varchar(45) NOT NULL, `name` varchar(45) NOT NULL, `points` int NOT NULL, `accomplishedcount` int NOT NULL, PRIMARY KEY (`steamid`))"
#define QUERY_LOAD_CONTRACTS			"SELECT `points`, `accomplishedcount` FROM contracts WHERE `steamid`=\"%s\""
#define QUERY_UPDATE_CONTRACTS			"UPDATE `contracts` SET `points`=\"%i\",`accomplishedcount`=\"%i\",`name`=\"%s\", WHERE `steamid`=\"%s\";"
#define QUERY_NEW_ENTRY					"INSERT INTO `contracts` (`steamid`,`name`,`points`,`accomplishedcount`) VALUES (\"%s\", '%s', %i, %i);"
#define QUERY_ALL_CONTRACTS				"SELECT `name`, `points`,`accomplishedcount` FROM `contracts` ORDER BY `points` DESC"
#define QUERY_CLEAR_CONTRACTS			"DELETE FROM `contracts`"
//Other plugins related stuff
#define STORE_NONE						"NONE"
#define STORE_ZEPHYRUS					"ZEPHYRUS"
#define STORE_SMSTORE					"SMSTORE"
#define STORE_SMRPG						"SMRPG"

EngineVersion engineName;

Handle CVAR_DBConfigurationName;
Handle CVAR_ChanceGetContract;
Handle CVAR_TeamRestrictions;
Handle CVAR_MinimumPlayers;
Handle CVAR_UsuedStore;

Handle TIMER_ContractsDistribution;
Handle DATABASE_Contract;
Handle ARRAY_Contracts;

bool IsInContract[MAXPLAYERS + 1];
bool IsInDatabase[MAXPLAYERS + 1];

int contractPoints[MAXPLAYERS + 1];
int contractReward[MAXPLAYERS + 1];
int contractProgress[MAXPLAYERS + 1];
int contractObjective[MAXPLAYERS + 1];
int contractAccomplishedCount[MAXPLAYERS + 1];

float distance;
float newPosition[3];
float lastPosition[MAXPLAYERS + 1][3];

char action[10];
char reward[10];
char weapon[10];
char chances[10];
char objective[10];
char contractName[100];
char contractType[MAXPLAYERS + 1][10];
char contractWeapon[MAXPLAYERS + 1][100];
char contractDescription[MAXPLAYERS + 1][100];

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DESCRIPTION, 
	version = PLUGIN_VERSION, 
	url = "http://www.sourcemod.net"
};

public void OnPluginStart()
{
	RegAdminCmd("sm_givecontract", CMD_GiveContract, ADMFLAG_GENERIC, "Give a contract to a user.");
	RegAdminCmd("sm_resetcontract", CMD_ResetContract, ADMFLAG_GENERIC, "Clear the contract table.");
	
	RegConsoleCmd("sm_contract", CMD_DisplayContractInfo, "Display your current contract info.");
	RegConsoleCmd("sm_contractlevel", CMD_DisplayContractRank, "Display your contract rank.");
	RegConsoleCmd("sm_contracttop", CMD_DisplayContractTop, "Display the first 10 best contract rank.");
	//RegConsoleCmd("sm_test", CMD_test);
	
	CVAR_DBConfigurationName = CreateConVar("sm_database_configuration_name", "storage-local", "Configuration name in database.cfg, by default, all results are saved in the sqlite database.");
	CVAR_ChanceGetContract = CreateConVar("sm_contract_chance_get_contract", "30", "The % of luck to get a new contract every 5 minutes.", _, true, 1.0);
	CVAR_TeamRestrictions = CreateConVar("sm_contract_teams", "2;3", "Team index wich can get contract. 2 = RED/T 3 = BLU/CT");
	CVAR_UsuedStore = CreateConVar("sm_contract_store_select", "NONE", "NONE=No store usage/ZEPHYRUS=use zephyrus store/SMSTORE=use sourcemod store");
	CVAR_MinimumPlayers = CreateConVar("sm_contract_minimum_players", "2", "How much player needed before receving an contract.", _, true, 1.0);
	
	HookEvent("player_death", OnPlayerDeath);
	
	engineName = GetEngineVersion();
	
	if (GetConVarInt(CVAR_MinimumPlayers) <= GetPlayerCount())
		TIMER_ContractsDistribution = CreateTimer(300.0, TMR_DistributeContracts, _, TIMER_REPEAT);
	
	if (engineName != Engine_CSS || engineName != Engine_CSGO)
		CreateTimer(0.5, TMR_UpdateHUD, _, TIMER_REPEAT);
	
	for (int z = 0; z < MaxClients; z++)
	{
		if (!IsValidClient(z))
			continue;
		
		GetClientAbsOrigin(z, lastPosition[z]);
		SDKHook(z, SDKHook_OnTakeDamage, OnTakeDamage);
	}
	
	LoadTranslations("common.phrases");
	LoadTranslations("contract.phrases");
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Store_GetClientCredits");
	MarkNativeAsOptional("Store_SetClientCredits");
	MarkNativeAsOptional("Store_GetClientAccountID");
	MarkNativeAsOptional("Store_GiveCreditsToUsers");
	MarkNativeAsOptional("SMRPG_AddClientExperience");
	
	return APLRes_Success;
}

public void OnConfigsExecuted()
{
	ReadConfigFile();
	
	char dbconfig[45];
	GetConVarString(CVAR_DBConfigurationName, dbconfig, sizeof(dbconfig));
	SQL_TConnect(GotDatabase, dbconfig);
}

public void OnClientConnected(int client)
{
	if (TIMER_ContractsDistribution == INVALID_HANDLE)
	{
		if (GetConVarInt(CVAR_MinimumPlayers) <= GetPlayerCount())
			TIMER_ContractsDistribution = CreateTimer(300.0, TMR_DistributeContracts, _, TIMER_REPEAT);
	}
	
	IsInContract[client] = false;
	
	LoadContracts(client);
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public void OnClientDisconnect(int client)
{
	if (!IsValidClient(client))
		return;
	
	if (TIMER_ContractsDistribution != INVALID_HANDLE)
	{
		if (GetConVarInt(CVAR_MinimumPlayers) > GetPlayerCount())
		{
			KillTimer(TIMER_ContractsDistribution);
			TIMER_ContractsDistribution = INVALID_HANDLE;
		}
	}
	
	SaveIntoDatabase(client);
}

//Event callback
public void OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	if (!IsValidClient(client) || (!IsInContract[client] && !IsInContract[attacker]))
		return;
	
	if (StrEqual(contractType[attacker], "HEADSHOT"))
	{
		int customkill = GetEventInt(event, "customkill");
		
		if (engineName == Engine_TF2)
		{
			if (GetEventInt(event, "death_flags") & TF_DEATHFLAG_DEADRINGER)
				return;
			
			if ((customkill == TF_CUSTOM_HEADSHOT || customkill == TF_CUSTOM_HEADSHOT_DECAPITATION))
			{
				contractProgress[attacker]++;
				VerifyContract(attacker);
			}
		}
		else if (engineName == Engine_CSGO || engineName == Engine_CSS)
		{
			if (GetEventInt(event, "headshot") == 1)
			{
				contractProgress[attacker]++;
				VerifyContract(attacker);
			}
		}
	}
	else if (StrEqual(contractType[client], "DIE"))
	{
		if (CheckKillMethod(client))
			contractProgress[client]++;
		
		if (IsInContract[attacker] && StrEqual(contractType[attacker], "KILL"))
		{
			if (CheckKillMethod(attacker))
				contractProgress[attacker]++;
			
			VerifyContract(attacker);
		}
		
		VerifyContract(client);
	}
	else if (StrEqual(contractType[attacker], "KILL"))
	{
		if (CheckKillMethod(attacker))
			contractProgress[attacker]++;
		
		VerifyContract(attacker);
	}
}

public Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	if (!IsValidClient(victim) || (!IsInContract[victim] && !IsInContract[attacker]))
		return Plugin_Continue;
	
	if (IsInContract[victim] && StrEqual(contractType[victim], "TAKE_DAMAGE"))
	{
		contractProgress[victim] += damage;
		VerifyContract(victim);
	}
	
	if(IsInContract[attacker] && StrEqual(contractType[attacker], "DEAL_DAMAGE"))
	{
		contractProgress[attacker] += damage;
		VerifyContract(attacker);
	}
	
	return Plugin_Continue;
}

//Command callback.
/*public Action CMD_test(int client, int args)
{
	OnClientDisconnect(client);
}*/

public Action CMD_ResetContract(int client, int args)
{
	if (client == 0)
		PrintToServer("[Contract] %t", "Database_reset");
	else
		CPrintToChat(client, "%s %t", PLUGIN_TAG, "Database_reset");
	
	for (int z = 0; z < MaxClients; z++)
	{
		IsInContract[z] = false;
		IsInDatabase[z] = false;
		
		contractPoints[z] = 0;
		contractAccomplishedCount[z] = 0;
	}
	
	SQL_FastQuery(DATABASE_Contract, QUERY_CLEAR_CONTRACTS);
	
	if (client == 0)
		PrintToServer("[Contract] %t", "Done");
	else
		CPrintToChat(client, "%s %t", PLUGIN_TAG, "Done");
}

public Action CMD_GiveContract(int client, int args)
{
	if (args < 1)
	{
		CPrintToChat(client, "%s %t", PLUGIN_TAG, "Contract_GiveUsage");
		return Plugin_Handled;
	}
	
	char arg1[45];
	GetCmdArg(1, arg1, sizeof(arg1));
	
	char target_name[MAX_TARGET_LENGTH];
	int target_list[MAXPLAYERS], target_count;
	bool tn_is_ml;
	
	if ((target_count = ProcessTargetString(
				arg1, 
				client, 
				target_list, 
				MAXPLAYERS, 
				COMMAND_FILTER_NO_BOTS, 
				target_name, 
				sizeof(target_name), 
				tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}
	
	for (int i = 0; i < target_count; i++)
	AssignateContract(target_list[i], true);
	
	CPrintToChat(client, "%s %t", PLUGIN_TAG, "Contract_GiveSucess", target_count);
	
	return Plugin_Handled;
}

public Action CMD_DisplayContractInfo(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;
	
	if (!IsInContract[client])
	{
		CPrintToChat(client, "%s %t", PLUGIN_TAG, "Contract_None");
		return Plugin_Handled;
	}
	
	CPrintToChat(client, "%s %t", PLUGIN_TAG, "Contract_Mission", contractDescription[client]);
	CPrintToChat(client, "%s %t", PLUGIN_TAG, "Contract_Progress", contractProgress[client], contractObjective[client]);
	CPrintToChat(client, "%s %t", PLUGIN_TAG, "Contract_Reward", contractReward[client]);
	
	return Plugin_Handled;
}

public Action CMD_DisplayContractRank(int client, int args)
{
	if (!IsValidClient(client))
		return Plugin_Handled;
	
	int target = -1;
	
	if (args == 0)
	{
		target = client;
	}
	else
	{
		char sTarget[45];
		GetCmdArg(1, sTarget, sizeof(sTarget));
		target = FindTarget(client, sTarget, true, false);
	}
	
	if (target == -1)
		CPrintToChat(client, "%s %t", PLUGIN_TAG, "Target_Invalid");
	
	if (client == target)
		CPrintToChat(client, "%s %t", PLUGIN_TAG, "Contract_CompletedInfoSelf", contractAccomplishedCount[client], contractPoints[client]);
	else
		CPrintToChat(client, "%s %t", PLUGIN_TAG, "Contract_CompletedInfoOther", target, contractAccomplishedCount[target], contractPoints[target]);
	
	return Plugin_Handled;
}

public Action CMD_DisplayContractTop(int client, int args)
{
	CPrintToChat(client, "%s %t", PLUGIN_TAG, "Database_LoadingTop");
	SQL_TQuery(DATABASE_Contract, T_GetTop10, QUERY_ALL_CONTRACTS, client);
	
	return Plugin_Handled;
}

//Function
public bool CheckKillMethod(int client)
{
	if (strlen(contractWeapon[client]) < 3)
		return true;
	
	char sWeapon[100];
	int aWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");
	if (IsValidEntity(aWeapon))
		GetEntPropString(aWeapon, Prop_Data, "m_iClassname", sWeapon, sizeof(sWeapon));
	
	if (StrEqual(contractWeapon[client], sWeapon))
	{
		return true;
	}
	else
	{
		if (engineName == Engine_TF2)
		{
			if (StrEqual(contractWeapon[client], "PRIMARY") && aWeapon == GetPlayerWeaponSlot(client, TFWeaponSlot_Primary))
				return true;
			else if (StrEqual(contractWeapon[client], "SECONDARY") && aWeapon == GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary))
				return true;
			else if (StrEqual(contractWeapon[client], "MELEE") && aWeapon == GetPlayerWeaponSlot(client, TFWeaponSlot_Melee))
				return true;
		}
		else if (engineName == Engine_CSGO || engineName == Engine_CSS)
		{
			if (StrEqual(contractWeapon[client], "PRIMARY") && aWeapon == GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY))
				return true;
			else if (StrEqual(contractWeapon[client], "SECONDARY") && aWeapon == GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY))
				return true;
			else if (StrEqual(contractWeapon[client], "MELEE") && aWeapon == GetPlayerWeaponSlot(client, CS_SLOT_KNIFE))
				return true;
		}
	}
	
	return false;
}

public void LoadContracts(int client)
{
	char query[100];
	char steamid[30];
	GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
	
	Format(query, sizeof(query), QUERY_LOAD_CONTRACTS, steamid);
	SQL_TQuery(DATABASE_Contract, T_GetPlayerInfo, query, client);
}

public void SendContract(int client, Handle contractInfos)
{
	char sObjectiv[100];
	char cWeapon[100];
	char cAction[10];
	char cName[100];
	int cObjective;
	int cReward;
	
	GetTrieString(contractInfos, FIELD_CONTRACT_NAME, cName, sizeof(cName));
	GetTrieString(contractInfos, FIELD_CONTRACT_ACTION, cAction, sizeof(cAction));
	GetTrieValue(contractInfos, FIELD_CONTRACT_OBJECTIVE, cObjective);
	GetTrieValue(contractInfos, FIELD_CONTRACT_REWARD, cReward);
	if (GetTrieString(contractInfos, FIELD_CONTRACT_WEAPON, cWeapon, sizeof(cWeapon)) && strlen(cWeapon) > 3)
	{
		contractWeapon[client] = cWeapon;
		Format(cWeapon, sizeof(cWeapon), " (%s)", cWeapon);
	}
	
	if (StrEqual(cAction, "WALK"))
		Format(sObjectiv, sizeof(sObjectiv), "%t", "Contract_Walk", cObjective);
	else if (StrEqual(cAction, "KILL"))
		Format(sObjectiv, sizeof(sObjectiv), "%t", "Contract_Kill", cObjective, cWeapon);
	else if (StrEqual(cAction, "HEADSHOT"))
		Format(sObjectiv, sizeof(sObjectiv), "%t", "Contract_Headshot", cObjective);
	else if (StrEqual(cAction, "DIE"))
		Format(sObjectiv, sizeof(sObjectiv), "%t", "Contract_Die", cObjective);
	
	contractReward[client] = cReward;
	contractProgress[client] = 0;
	contractObjective[client] = cObjective;
	contractType[client] = cAction;
	Format(contractDescription[client], sizeof(contractDescription[]), "%s - %s", cName, sObjectiv);
	
	char phrases[100];
	Format(cName, sizeof(cName), "%t - %s", "Contract_New", cName);
	Panel menu = new Panel();
	SetPanelTitle(menu, cName);
	Format(phrases, sizeof(phrases), "%t", "menu_objectiv");
	DrawPanelItem(menu, phrases, ITEMDRAW_RAWLINE);
	DrawPanelItem(menu, sObjectiv, ITEMDRAW_RAWLINE);
	Format(phrases, sizeof(phrases), "%t", "menu_accept");
	DrawPanelItem(menu, phrases, ITEMDRAW_RAWLINE);
	Format(phrases, sizeof(phrases), "%t", "menu_yes");
	DrawPanelItem(menu, phrases);
	Format(phrases, sizeof(phrases), "%t", "menu_no");
	DrawPanelItem(menu, phrases);
	SendPanelToClient(menu, client, MenuHandle_MainMenu, MENU_TIME_FOREVER);
}

public void VerifyContract(int client)
{
	if (contractProgress[client] < contractObjective[client])
		return;
	
	IsInContract[client] = false;
	
	contractAccomplishedCount[client]++;
	contractPoints[client] += contractReward[client];
	
	SaveIntoDatabase(client);
	
	char store[15];
	GetConVarString(CVAR_UsuedStore, store, sizeof(store));
	
	if (StrEqual(store, STORE_ZEPHYRUS))
	{
		Store_SetClientCredits(client, Store_GetClientCredits(client) + contractReward[client]);
	}
	else if (StrEqual(store, STORE_SMSTORE))
	{
		int id[1];
		id[0] = Store_GetClientAccountID(client);
		Store_GiveCreditsToUsers(id, 1, contractReward[client]);
	}
	else if (StrEqual(store, STORE_SMRPG))
	{
		SMRPG_SetClientExperience(client, SMRPG_GetClientExperience(client) + contractReward[client]);
	}
	
	CPrintToChat(client, "%s %t", PLUGIN_TAG, "Contract_ThankYou");
	CPrintToChat(client, "%s %t", PLUGIN_TAG, "Contract_ThankReward", contractReward[client]);
}

public void SaveIntoDatabase(int client)
{
	char query[400];
	char steamid[30];
	char clientName[45];
	
	if (!GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid)))
		return;
	
	GetClientNameForDatabase(DATABASE_Contract, client, clientName, sizeof(clientName));
	
	if (IsInDatabase[client])
	{
		Format(query, sizeof(query), QUERY_UPDATE_CONTRACTS, contractPoints[client], contractAccomplishedCount[client], clientName, steamid);
		PrintToConsole(client, query);
		SQL_FastQuery(DATABASE_Contract, query);
	}
	else
	{
		Format(query, sizeof(query), QUERY_NEW_ENTRY, steamid, clientName, contractPoints[client], contractAccomplishedCount[client]);
		PrintToConsole(client, query);
		SQL_FastQuery(DATABASE_Contract, query);
	}
}

public void AssignateContract(int client, bool force)
{
	float pourcent = GetConVarFloat(CVAR_ChanceGetContract) / 100.0;
	
	if (!force && GetRandomFloat(0.0, 1.0) < pourcent)
		return;
	
	int contractCount = GetArraySize(ARRAY_Contracts);
	while (contractCount > 0)
	{
		contractCount--;
		
		Handle TRIE_Contract = GetArrayCell(ARRAY_Contracts, contractCount);
		GetTrieValue(TRIE_Contract, FIELD_CONTRACT_CHANCES, pourcent);
		
		if (GetRandomFloat(0.0, 1.0) > pourcent)
			continue;
		
		SendContract(client, TRIE_Contract);
		
		break;
	}
	
	if (force)
	{
		Handle TRIE_Contract = GetArrayCell(ARRAY_Contracts, GetRandomInt(0, GetArraySize(ARRAY_Contracts) - 1));
		GetTrieValue(TRIE_Contract, FIELD_CONTRACT_CHANCES, pourcent);
		SendContract(client, TRIE_Contract);
	}
}

//Timer callback
public Action TMR_UpdateHUD(Handle tmr)
{
	for (new i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && IsPlayerAlive(i) && IsInContract[i])
		{
			GetClientAbsOrigin(i, newPosition);
			distance = GetVectorDistance(lastPosition[i], newPosition);
			lastPosition[i] = newPosition;
			if (distance / 20 >= 1 && StrEqual(contractType[i], "WALK"))
			{
				contractProgress[i] += 1;
				VerifyContract(i);
			}
		}
	}
	
	for (int z = 0; z < MaxClients; z++)
	{
		if (!IsInContract[z] || !IsValidClient(z))
			continue;
		
		SetHudTextParams(0.02, 0.0, 0.8, 255, 0, 0, 200);
		ShowHudText(z, -1, contractDescription[z]);
		SetHudTextParams(0.02, 0.03, 0.8, 255, 0, 0, 200);
		ShowHudText(z, -1, "%i / %i", contractProgress[z], contractObjective[z]);
	}
}

public Action TMR_DistributeContracts(Handle tmr)
{
	char teams[10];
	char team[3];
	GetConVarString(CVAR_TeamRestrictions, teams, sizeof(teams));
	for (int z = 0; z < MaxClients; z++)
	{
		if (!IsValidClient(z) || IsInContract[z])
			continue;
		
		IntToString(GetClientTeam(z), team, sizeof(team));
		if (StrContains(teams, team) == -1)
			continue;
		
		AssignateContract(z, false);
	}
}

//Menu Handlers
public MenuHandle_MainMenu(Handle menu, MenuAction menuAction, int client, int itemIndex)
{
	if (menuAction == MenuAction_Select)
	{
		if (itemIndex == 1)
			IsInContract[client] = true;
		else if (itemIndex == 2)
			IsInContract[client] = false;
	}
	else
	{
		CloseHandle(menu);
	}
}

public int MenuHandler_Top(Handle menu, MenuAction menuAction, int param1, int param2)
{
	if (menuAction == MenuAction_End)
		CloseHandle(menu);
}

//Database related stuff
public GotDatabase(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == INVALID_HANDLE)
	{
		SetFailState("%t", "Database_Failure", error);
		return;
	}
	
	DATABASE_Contract = hndl;
	
	char buffer[300];
	if (!SQL_FastQuery(DATABASE_Contract, QUERY_INIT_DATABASE))
	{
		SQL_GetError(DATABASE_Contract, buffer, sizeof(buffer));
		SetFailState("%s", buffer);
	}
	for (int z = 0; z < MaxClients; z++)
	{
		if (!IsValidClient(z))
			continue;
		
		LoadContracts(z);
	}
}

public void T_GetTop10(Handle db, Handle results, const char[] error, any data)
{
	int client = data;
	
	if (client == 0)
		return;
	
	if (results == INVALID_HANDLE)
	{
		CPrintToChat(client, "%t", "Database_ErrorTopPlayer", PLUGIN_TAG);
		LogError("Query failed >>> %s", error);
		return;
	}
	
	Handle menu = CreateMenu(MenuHandler_Top);
	SetMenuTitle(menu, "%t", "Contract_MTopSeven");
	
	char name[45];
	char menuEntry[100];
	
	int points = 0;
	int count = 7;
	int accomplishedcount = 0;
	while (SQL_FetchRow(results))
	{
		if (count <= 0)
			break; //I could use MySQL but nah.
		SQL_FetchString(results, 0, name, sizeof(name));
		points = SQL_FetchInt(results, 1);
		accomplishedcount = SQL_FetchInt(results, 2);
		Format(menuEntry, sizeof(menuEntry), "%t", "Contract_MenuItem", name, points, accomplishedcount);
		AddMenuItem(menu, "-", menuEntry, ITEMDRAW_DISABLED);
		count--;
	}
	
	DisplayMenu(menu, client, 40);
	
	CloseHandle(results);
}

public void T_GetPlayerInfo(Handle db, Handle results, const char[] error, any data)
{
	int client = data;
	if (!IsValidClient(client))
		return;
	
	if (!SQL_FetchRow(results))
	{
		IsInDatabase[client] = false;
	}
	else
	{
		contractPoints[client] = SQL_FetchInt(results, 0);
		contractAccomplishedCount[client] = SQL_FetchInt(results, 1);
		IsInDatabase[client] = true;
	}
}

//Stocks
stock bool ReadConfigFile()
{
	ARRAY_Contracts = CreateArray();
	
	char path[100];
	Handle kv = CreateKeyValues("Contracts Options");
	BuildPath(Path_SM, path, sizeof(path), "/configs/contracts.cfg");
	FileToKeyValues(kv, path);
	
	if (!KvGotoFirstSubKey(kv))
		return;
	
	do
	{
		KvGetString(kv, FIELD_CONTRACT_NAME, contractName, sizeof(contractName));
		KvGetString(kv, FIELD_CONTRACT_ACTION, action, sizeof(action));
		KvGetString(kv, FIELD_CONTRACT_OBJECTIVE, objective, sizeof(objective));
		KvGetString(kv, FIELD_CONTRACT_CHANCES, chances, sizeof(chances));
		KvGetString(kv, FIELD_CONTRACT_REWARD, reward, sizeof(reward));
		KvGetString(kv, FIELD_CONTRACT_WEAPON, weapon, sizeof(weapon));
		
		Handle tmpTrie = CreateTrie();
		SetTrieString(tmpTrie, FIELD_CONTRACT_NAME, contractName, false);
		SetTrieString(tmpTrie, FIELD_CONTRACT_ACTION, action, false);
		SetTrieValue(tmpTrie, FIELD_CONTRACT_OBJECTIVE, StringToInt(objective), false);
		SetTrieValue(tmpTrie, FIELD_CONTRACT_CHANCES, (StringToFloat(chances) / 100.0), false);
		SetTrieValue(tmpTrie, FIELD_CONTRACT_REWARD, StringToInt(reward), false);
		SetTrieString(tmpTrie, FIELD_CONTRACT_WEAPON, weapon, false);
		
		PushArrayCell(ARRAY_Contracts, tmpTrie);
		
	} while (KvGotoNextKey(kv));
	
	CloseHandle(kv);
}

//https://forums.alliedmods.net/showpost.php?p=2457161&postcount=9
stock void GetClientNameForDatabase(Handle db, int client, char[] buffer, int bufferSize) //buffer[2*MAX_NAME_LENGTH+2])??
{
	GetClientName(client, buffer, bufferSize);
	SQL_EscapeString(db, buffer, buffer, bufferSize);
}

stock int GetPlayerCount()
{
	int count = 0;
	for (int i = 0; i < MaxClients; i++)
	{
		if (IsValidClient(i))
			count++;
	}
	
	return count;
}

stock bool IsValidClient(iClient, bool bReplay = true)
{
	if (iClient <= 0 || iClient > MaxClients)
		return false;
	if (!IsClientInGame(iClient))
		return false;
	if (bReplay && (IsClientSourceTV(iClient) || IsClientReplay(iClient)))
		return false;
	return true;
} 