#include <stdint.h>
#include <string.h>
#include <math.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "silly.h"

#define POOL_CAP 128
#define MIN_DIST 0.1f
#define LIFE_TIME 60 * 1000 //小兵只能存活60秒
#define UPVAL_ENTITIES 1
#define UPVAL_FIGHTING 2

enum entity_type {
	ENTITY_SOLDIER = 0,
	ENTITY_TOWER = 1,
};

enum entity_action {
	ACTION_NONE = 0,
	ACTION_FOLLOW = 1,
	ACTION_BATTLE = 2,
};

struct entity {
	int64_t createms;
	uint64_t uid;
	uint64_t lid;
	int next;
	int dead;
	int target;
	float x;
	float z;
	enum entity_type type;
	enum entity_action action;
};

struct world {
	int64_t nowms;
	int entity_alive;
	int entity_free;
	int entities_cap;
	struct entity *entities;
	int stk_entities;
	int stk_fighting;
};

static int lgc(lua_State *L)
{
	struct world *w = lua_touserdata(L, 1);
	if (w->entities != NULL) {
		free(w->entities);
		w->entities = NULL;
		w->entities_cap = 0;
		w->entity_alive = -1;
		w->entity_free = -1;
	}
	return 0;
}

static void expand_entities(struct world *w, int cap)
{
	int start = w->entities_cap;
	int end = cap - 1;
	assert(cap > w->entities_cap);
	struct entity *new_entities =
		realloc(w->entities, cap * sizeof(struct entity));
	assert(new_entities); //OOM
	w->entities = new_entities;
	memset(&w->entities[start], 0, (cap - start) * sizeof(struct entity));
	for (int i = start; i < end; i++) {
		w->entities[i].next = i + 1;
	}
	w->entities[end].next = w->entity_free;
	w->entity_free = start;
	w->entities_cap = cap;
}

static inline float entity_match_radius(const struct entity *e)
{
	switch (e->type) {
	case ENTITY_SOLDIER:
		return 3.f;
	case ENTITY_TOWER:
		return 2.f;
	default:
		assert(!"unsupport type");
		return 0.f;
	}
}

static inline float entity_attack_radius(const struct entity *e)
{
	switch (e->type) {
	case ENTITY_SOLDIER:
		return 0.3f;
	case ENTITY_TOWER: //塔不会攻击
		return -0.1f;
	default:
		assert(!"unsupport type");
		return 0.f;
	}
}

static inline float entity_speed(const struct entity *e)
{
	if (e->type == ENTITY_SOLDIER)
		return 0.5f;
	else
		return 0.0;
}

static inline float distance(const struct entity *e1, const struct entity *e2)
{
	float dx = e1->x - e2->x;
	float dz = e1->z - e2->z;
	return dx * dx + dz * dz;
}

static inline int entity_id(const struct world *w, const struct entity *e)
{
	if (e == NULL)
		return -1;
	return (int)(e - w->entities);
}

static int find_target(struct world *w, const struct entity *e, float *radius)
{
	int ei = w->entity_alive;
	const struct entity *target = NULL;
	float closest_distance = *radius;
	while (ei >= 0) {
		float dist;
		const struct entity *ee = &w->entities[ei];
		ei = ee->next;
		if ((e->lid != 0 && e->lid == ee->lid) || e->uid == ee->uid) {
			continue;
		}
		dist = distance(e, ee);
		if (dist > closest_distance)
			continue;
		closest_distance = dist;
		target = ee;
	}
	*radius = closest_distance;
	return entity_id(w, target);
}

#define set_int(L, t, k, n)    \
	lua_pushinteger(L, n); \
	lua_setfield(L, t, k)

#define seti_int(L, t, k, n)   \
	lua_pushinteger(L, n); \
	lua_seti(L, t, k)

#define set_float(L, t, k, n) \
	lua_pushnumber(L, n); \
	lua_setfield(L, t, k)

#define set_nil(L, t, k) \
	lua_pushnil(L);  \
	lua_setfield(L, t, k)

#define seti_nil(L, t, k) \
	lua_pushnil(L);   \
	lua_seti(L, t, k)

#define set_bool(L, t, k, n)   \
	lua_pushboolean(L, n); \
	lua_setfield(L, t, k)

#define seti_bool(L, t, k, n)  \
	lua_pushboolean(L, n); \
	lua_seti(L, t, k)

struct upctx {
	int stk_entities;
	int stk_fighting;
};

static struct upctx build_upctx(lua_State *L, int stk_world)
{
	struct upctx ctx;
	lua_getiuservalue(L, stk_world, UPVAL_ENTITIES);
	ctx.stk_entities = lua_gettop(L);
	lua_getiuservalue(L, stk_world, UPVAL_FIGHTING);
	ctx.stk_fighting = lua_gettop(L);
	return ctx;
}

static void sync_entity(lua_State *L, struct upctx ctx, int eid,
			struct entity *e)
{
	int type = lua_geti(L, ctx.stk_entities, eid);
	int t = lua_gettop(L);
	if (type == LUA_TNIL) {
		lua_pop(L, 1);
		lua_createtable(L, 0, 7);
		lua_pushvalue(L, -1);
		lua_seti(L, ctx.stk_entities, eid);
		set_int(L, t, "eid", eid);
		set_int(L, t, "uid", e->uid);
		set_int(L, t, "lid", e->lid);
		set_int(L, t, "etype", e->type);
	}
	if (e->target >= 0) {
		set_int(L, t, "target", e->target);
	} else {
		set_nil(L, t, "target");
	}
	set_float(L, t, "x", e->x);
	set_float(L, t, "z", e->z);
	set_int(L, t, "type", e->type);
	set_int(L, t, "action", e->action);
	set_bool(L, t, "dead", e->dead);
	if (e->action == ACTION_BATTLE) {
		lua_pushvalue(L, t);
		lua_seti(L, ctx.stk_fighting, eid);
	} else {
		seti_nil(L, ctx.stk_fighting, eid);
	}
}

static int lnew(lua_State *L)
{
	struct world *w = lua_newuserdatauv(L, sizeof(*w), 2);
	lua_pushvalue(L, 2);
	lua_setiuservalue(L, -2, UPVAL_ENTITIES);
	lua_pushvalue(L, 3);
	lua_setiuservalue(L, -2, UPVAL_FIGHTING);
	if (luaL_newmetatable(L, "lib.world")) {
		lua_pushcfunction(L, lgc);
		lua_setfield(L, -2, "__gc");
	}
	lua_setmetatable(L, -2);
	w->nowms = (int64_t)luaL_checkinteger(L, 1);
	w->entities_cap = 0;
	w->entities = NULL;
	w->entity_free = -1;
	w->entity_alive = -1;
	expand_entities(w, POOL_CAP);
	return 1;
}

/// @field enter fun(w:lib.world, uid:integer, lid:integer,
///	x:number, z:number, type:integer):integer
static int lenter(lua_State *L)
{
	int eid;
	struct world *w;
	struct entity *e;
	struct upctx ctx;
	w = luaL_checkudata(L, 1, "lib.world");
	if (w->entity_free == -1) {
		expand_entities(w, 2 * w->entities_cap);
	}
	e = &w->entities[w->entity_free];
	w->entity_free = e->next;
	e->dead = 0;
	e->createms = w->nowms;
	e->uid = (uint64_t)luaL_checkinteger(L, 2);
	e->lid = (uint64_t)luaL_checkinteger(L, 3);
	e->x = (float)luaL_checknumber(L, 4);
	e->z = (float)luaL_checknumber(L, 5);
	e->type = (enum entity_type)luaL_checkinteger(L, 6);
	e->target = -1;
	e->action = ACTION_NONE;
	eid = entity_id(w, e);
	e->next = w->entity_alive;
	w->entity_alive = eid;
	ctx = build_upctx(L, 1);
	sync_entity(L, ctx, eid, e);
	lua_pop(L, 2);
	lua_pushinteger(L, eid);
	return 1;
}

static int ldead(lua_State *L)
{
	struct world *w = luaL_checkudata(L, 1, "lib.world");
	int eid = (int)luaL_checkinteger(L, 2);
	struct entity *e = &w->entities[eid];
	if (e->dead == 0) {
		e->dead = 1;
	}
	return 0;
}

static void update_position(lua_State *L, struct world *w, float delta_time,
			    struct upctx ctx)
{
	int *prev = &w->entity_alive;
	//第一遍先更新小兵位置
	for (int ei = w->entity_alive; ei >= 0;) {
		float speed;
		struct entity *ef;
		const struct entity *et;
		int eid = ei;
		ef = &w->entities[ei];
		ei = ef->next;
		if (ef->dead != 0 ||
		    ef->createms + LIFE_TIME <= w->nowms) { //寿命到头了, 释放掉
			seti_nil(L, ctx.stk_entities, eid);
			seti_nil(L, ctx.stk_fighting, eid);
			ef->next = w->entity_free;
			w->entity_free = eid;
			continue;
		}
		*prev = eid;
		prev = &ef->next;
		if (ef->target < 0) {
			continue;
		}
		speed = entity_speed(ef);
		if (speed <= 0.f) {
			continue;
		}
		et = &w->entities[ef->target];
		float dx = et->x - ef->x;
		float dz = et->z - ef->z;
		float dist = sqrtf(dx * dx + dz * dz);
		if (dist <= MIN_DIST) { //已经很接近了, 不用走了
			continue;
		}
		float delta_dist = speed * delta_time;
		ef->x += dx / dist * delta_dist;
		ef->z += dz / dist * delta_dist;
	}
	*prev = -1;
}

static int update_one(struct world *w, struct entity *ef)
{
	int dirty = 0;
	float match_radius;
	float attack_radius;
	if (ef->target >= 0 &&
	    w->entities[ef->target].dead) { //上次有匹配的对象, 并且死了
		ef->target = -1;
		ef->action = ACTION_NONE;
		dirty = 1;
	}
	if (ef->action == ACTION_BATTLE) { //正在战斗中, 不处理
		return dirty;
	}
	match_radius = entity_match_radius(ef);
	attack_radius = entity_attack_radius(ef);
	if (ef->target >= 0) { //上次有匹配的对象
		float dist = distance(ef, &w->entities[ef->target]);
		if (dist <= attack_radius) { //已经可以攻击了
			ef->action = ACTION_BATTLE;
			dirty = 1;
			return dirty;
		}
		if (dist <= match_radius) { //还在匹配范围内, 继续保持
			return dirty;
		}
		//上次匹配的人已经走远了，需要重新匹配
	}
	ef->target = find_target(w, ef, &match_radius);
	if (ef->target < 0) { //没有找到匹配的对象
		return dirty;
	}
	if (match_radius < attack_radius) { //已经可以攻击了
		ef->action = ACTION_BATTLE;
	} else {
		ef->action = ACTION_FOLLOW;
	}
	return 1;
}

static void update_match(lua_State *L, struct world *w, struct upctx ctx)
{
	for (int ei = w->entity_alive; ei >= 0;) {
		int eid = ei;
		struct entity *e = &w->entities[eid];
		ei = e->next;
		if (update_one(w, e)) {
			sync_entity(L, ctx, eid, e);
		}
	}
}

static int ltick(lua_State *L)
{
	struct upctx ctx;
	struct world *w = luaL_checkudata(L, 1, "lib.world");
	//delta 转化为秒
	int64_t nowms = luaL_checkinteger(L, 2);
	float delta_time = (float)(nowms - w->nowms) / 1001.f;
	w->nowms = nowms;
	ctx = build_upctx(L, 1);
	update_position(L, w, delta_time, ctx);
	update_match(L, w, ctx);
	lua_pop(L, 2);
	return 1;
}

//dump(entities, free)
static int ldump(lua_State *L)
{
	int i = 0;
	const struct world *w = luaL_checkudata(L, 1, "lib.world");
	for (int ei = w->entity_alive; ei >= 0;) {
		int eid = ei;
		ei = w->entities[ei].next;
		++i;
		seti_int(L, 2, i, eid);
	}
	i = 0;
	for (int ei = w->entity_free; ei >= 0;) {
		int eid = ei;
		ei = w->entities[ei].next;
		++i;
		seti_int(L, 3, i, eid);
	}
	lua_pushinteger(L, w->entities_cap);
	return 1;
}

int luaopen_lib_world(lua_State *L)
{
	///@class lib.world
	luaL_Reg tbl[] = {
		{ "new",   lnew   },
		{ "enter", lenter },
		{ "dead",  ldead  },
		{ "tick",  ltick  },
		{ "dump",  ldump  },
		//end
		{ NULL,    NULL   },
	};
	luaL_newlib(L, tbl);
	if (luaL_newmetatable(L, "lib.world")) {
		lua_pushvalue(L, -2);
		lua_setfield(L, -2, "__index");
		lua_pushcfunction(L, lgc);
		lua_setfield(L, -2, "__gc");
	}
	return 2;
}
