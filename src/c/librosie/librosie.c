/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/* librosie.c    Expose the Rosie API                                        */
/*                                                                           */
/*  © Copyright IBM Corporation 2016.                                        */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */


/* ROSIE_HOME defined on the command line during compilation (see Makefile)  */

#ifndef ROSIE_HOME
#error "ROSIE_HOME not defined.  Check CFLAGS in Makefile?"
#endif

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

#include "lauxlib.h"
#include "lualib.h"

static lua_State *single_instanceL = NULL;	    /* !@# Make a table? */

static lua_State *globalL = NULL;
static const char *progname = "librosie";

/*
 * Hook set by signal function to stop the interpreter.
 */
static void lstop (lua_State *L, lua_Debug *ar) {
  (void)ar;  /* unused arg. */
  lua_sethook(L, NULL, 0, 0);  /* reset hook */
  luaL_error(L, "interrupted!");
}

/*
 * Function to be called at a C signal. Because a C signal cannot
 * just change a Lua state (as there is no proper synchronization),
 * this function only sets a hook that, when called, will stop the
 * interpreter.
 */
static void laction (int i) {
  signal(i, SIG_DFL); /* if another SIGINT happens, terminate process */
  lua_sethook(globalL, lstop, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}

/*
 * Prints an error message, adding the program name in front of it
 * (if present)
 */
void l_message (const char *pname, const char *msg) {
  if (pname) lua_writestringerror("%s: ", pname);
  lua_writestringerror("%s\n", msg);
}

/*
 * Check whether 'status' is not OK and, if so, prints the error
 * message on the top of the stack. It assumes that the error object
 * is a string, as it was either generated by Lua or by 'msghandler'.
 */
static int report (lua_State *L, int status) {
  if (status != LUA_OK) {
    const char *msg = lua_tostring(L, -1);
    l_message(progname, msg);
    lua_pop(L, 1);  /* remove message */
  }
  return status;
}

/*
 * Message handler used to run all chunks
 */
static int msghandler (lua_State *L) {
  const char *msg = lua_tostring(L, 1);
  if (msg == NULL) {  /* is error object not a string? */
    if (luaL_callmeta(L, 1, "__tostring") &&  /* does it have a metamethod */
        lua_type(L, -1) == LUA_TSTRING)  /* that produces a string? */
      return 1;  /* that is the message */
    else
      msg = lua_pushfstring(L, "(error object is a %s value)",
                               luaL_typename(L, 1));
  }
  luaL_traceback(L, L, msg, 1);  /* append a standard traceback */
  return 1;  /* return the traceback */
}

/*
 * Interface to 'lua_pcall', which sets appropriate message function
 * and C-signal handler. Used to run all chunks.
 */
static int docall (lua_State *L, int narg, int nres) {
  int status;
  int base = lua_gettop(L) - narg;  /* function index */
  lua_pushcfunction(L, msghandler);  /* push message handler */
  lua_insert(L, base);  /* put it under function and args */
  globalL = L;  /* to be available to 'laction' */
  signal(SIGINT, laction);  /* set C-signal handler */
  status = lua_pcall(L, narg, nres, base);
  signal(SIGINT, SIG_DFL); /* reset C-signal handler */
  lua_remove(L, base);  /* remove message handler from the stack */
  return status;
}

static int dochunk (lua_State *L, int status) {
  if (status == LUA_OK) status = docall(L, 0, 0);
  return report(L, status);
}

#if 0
static int dofile (lua_State *L, const char *name) {
  return dochunk(L, luaL_loadfile(L, name));
}
#endif

static int dostring (lua_State *L, const char *s, const char *name) {
  return dochunk(L, luaL_loadbuffer(L, s, strlen(s), name));
}

static void stackDump (lua_State *L) {
      int i;
      int top = lua_gettop(L);
      for (i = 1; i <= top; i++) {
        int t = lua_type(L, i);
        switch (t) {
    
          case LUA_TSTRING:  /* strings */
	       printf("%d: `%s'", i, lua_tostring(L, i));
            break;
    
          case LUA_TBOOLEAN:  /* booleans */
	       printf("%d: %s", i, (lua_toboolean(L, i) ? "true" : "false"));
            break;
    
          case LUA_TNUMBER:  /* numbers */
	       printf("%d: %g", i, lua_tonumber(L, i));
            break;
    
          default:  /* other values */
	       printf("%d: %s", i, lua_typename(L, t));
            break;
    
        }
        printf("  ");  /* put a separator */
      }
      printf("\n");  /* end the listing */
    }

#define TRUE 1
#define FALSE 0

#define SET_ROSIE_HOME(val) SET_ROSIE_HOME_HELPER(val)
#define SET_ROSIE_HOME_HELPER(thing) QUOTE(ROSIE_HOME = #thing)

#define QUOTE_EXPAND(name) QUOTE(name)		    /* expand name */
#define QUOTE(thing) #thing			    /* stringify it */

#define MAXPATHSIZE 4096
int bootstrap (const char *rosie_home) {
     lua_State *L = single_instanceL;
     char name[MAXPATHSIZE + 1];
     if (strlcpy(name, rosie_home, sizeof(name)) >= sizeof(name))
	  luaL_error(L, "error during bootstrap: MAXPATHSIZE too small");
     if (strlcat(name, "/src/bootstrap.lua", sizeof(name)) >= sizeof(name))
	  luaL_error(L, "error during bootstrap: MAXPATHSIZE too small");
     return dochunk(L, luaL_loadfile(L, name));
}

void require (const char *name, int assign_name) {
     int status;
     lua_State *L = single_instanceL;
     lua_getglobal(L, "require");
     lua_pushstring(L, name);
     status = docall(L, 1, 1);                   /* call 'require(name)' */
     if (status != LUA_OK) {
	  l_message(progname, lua_pushfstring(L, "error requiring %s (%s)", name, lua_tostring(L, -1)));
	  exit(-1);
     }
     if (assign_name==TRUE) {			 /* set the global to the return value of 'require' */
	  lua_setglobal(L, name);
     }
     else {
	  lua_pop(L, 1);		   /* else discard the result of require */
     };
}

lua_State *get_L() { return single_instanceL; }

void initialize(const char *rosie_home) {

     int status;

  lua_State *L = luaL_newstate();
  if (L == NULL) {
       l_message((char *)'\0', "cannot create lua state: not enough memory");
    exit(-2);
  }

    single_instanceL = L;




/* 
   luaL_checkversion checks whether the core running the call, the core that created the Lua state,
   and the code making the call are all using the same version of Lua. Also checks whether the core
   running the call and the core that created the Lua state are using the same address space.
*/   
  luaL_checkversion(L);

  luaL_openlibs(L);				    /* open standard libraries */



     int stkpos = lua_gettop(L);

     const char *setup = SET_ROSIE_HOME(ROSIE_HOME); /* !@# */
     status = dostring (L, setup, "set ROSIE_HOME");
     report(L, status);
     if (status != LUA_OK) exit(-1);
  
     /* status = bootstrap(QUOTE_EXPAND(ROSIE_HOME)); */
     /* if (status != LUA_OK) exit(-1); */

     /* lua_getglobal(L, "bootstrap"); */
     /* lua_insert(L, 1); */
     /* status = lua_pcall(L, 0, 0, 0); */
     /* if (status != LUA_OK) { */
     /* 	  l_message(progname, lua_pushfstring(L, "error during bootstrap (%s)", */
     /* 					      lua_tostring(L, -1))); */
     /* 	  exit(-1); */
     /* } */
  
     require( "repl", FALSE);
     require( "api", TRUE);

     if (lua_gettop(L)!=stkpos)
	  printf("WARNING: after initialization, top should be %d but was %d\n",
		 stkpos,
		 lua_gettop(L));
}



int rosie_api(const char *name, ...) {

     va_list args;
     char *arg;
     int base;
     
     lua_State *L = single_instanceL;

     int nargs = 2;		   /* get this later from a table */

     printf("Calling Rosie api: %s\n", name);

     va_start(args, name);	   /* setup variadic arg processing */

     printf("Stack at start of rosie_api:\n");
     stackDump(L);
     base = lua_gettop(L);			    /* save top pointer */
     /* printf("Base of stack is %d\n", base); */

     /* Optimize later: memoize stack value of fcn for each api call to avoid this lookup? */

     lua_getglobal(L, "api");
     lua_getfield(L, -1 , name);                    /* -1 is stack top, i.e. api table */
     lua_remove(L, base+1);			    /* remove the api table from the stack */
     /* Later: insert a check HERE to ensure the value we get is a function */

     for (int i = 1; i <= nargs; i++) {
	  arg = va_arg(args, char *);   /* get the next arg */
	  lua_pushstring(L, arg);	/* push it */
     }

     va_end(args);

     lua_call(L, nargs, LUA_MULTRET); 

     /* printf("Stack immediately after lua_call:\n"); */
     /* stackDump(L); */
     
     /* printf("base+1 value from stack as a boolean: %s\n", lua_toboolean(L, base+1) ? "true" : "false"); */
     /* printf("base+1 value from stack as a string: %s\n", lua_tostring(L, base+1)); */

     if (lua_isboolean(L, base+1) != TRUE) {
	  l_message(progname, lua_pushfstring(L, "api error: first return value of %s not a boolean", name));
	  exit(-1);
     }

     int ok = lua_toboolean(L, base+1);
     if (ok != TRUE) {
	       printf("== In api error handler ==\n");
	       stackDump(L);
	       l_message(progname, lua_pushfstring(L, "lua error in rosie api call '%s': %s", name, lua_tostring(L, -1)));
	       exit(-1);
	  }

     lua_remove(L, base+1);			    /* remove the boolean retval of api call */

     printf("Stack at end of call to Rosie api: %s\n", name);
     stackDump(L);

     
     return LUA_OK;
}

