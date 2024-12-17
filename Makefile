.PNONY:all
INCLUDE :=

include silly/Platform.mk

linux macosx: all

LUA_INC=silly/deps/lua
LIB_DIR=lualib-src
INCLUDE += -I $(LUA_INC) -I silly/silly-src/

LIB_PATH=luaclib
LIB_FILE = \
	lualib-world.c \

LIB_SRC = $(addprefix $(LIB_DIR)/, $(LIB_FILE))

all: \
	fmt 			\
	silly/silly		\
	$(LIB_PATH)/lib.so	\

$(LIB_PATH):
	mkdir $(LUACLIB_PATH)

silly/silly:
	make -C silly

$(LIB_PATH)/lib.so: $(LIB_SRC) | $(LIB_PATH)
	$(CC) $(CCFLAG) $(INCLUDE) -o $@ $^ $(SHARED)
fmt:
	clang-format -i lualib-src/lua*.c

