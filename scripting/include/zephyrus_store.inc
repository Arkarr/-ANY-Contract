native Store_RegisterHandler(String:type[], String:uniquekey[], Function:mapstart, Function:reset, Function:config, Function:use, Function:remove, bool:equipable = true, bool:raw = false);
native Store_RegisterMenuHandler(String:identifier[], Function:menu, Function:handler);
native Store_SetDataIndex(itemid, index);
native Store_GetDataIndex(itemid);
native Store_GetEquippedItem(client, String:type[], slot=0);
native Store_IsClientLoaded(client);
native Store_DisplayPreviousMenu(client);
native Store_SetClientMenu(client, num);
native Store_GetClientCredits(client);
native Store_SetClientCredits(client, credits);
native Store_IsClientVIP(client);
native Store_IsItemInBoughtPackage(client, itemid, uid=-1);
native Store_ShouldConfirm();
native Store_DisplayConfirmMenu(client, String:title[], Function:callback, data);
native Store_GiveItemZephyrus(client, itemid, purchase=0, expiration=0, price=0);
native Store_RemoveItem(client, itemid);
native Store_GetClientTarget(client);

forward Store_OnClientModelChanged(client, String:model[]);

public Extension:__ext_store_sm =
{
	name = "Store - The Resurrection",
	file = "store_sm.ext",
#if defined AUTOLOAD_EXTENSIONS
	autoload = 1,
#else
	autoload = 0,
#endif
	required = 0,
};