/*  -*- Mode: C/l; -*-                                                       */
/*                                                                           */
/*  librosie.h                                                               */
/*                                                                           */
/*  © Copyright IBM Corporation 2016, 2017.                                  */
/*  LICENSE: MIT License (https://opensource.org/licenses/mit-license.html)  */
/*  AUTHOR: Jamie A. Jennings                                                */

#define INITIAL_RPLX_SLOTS 32
#define INITIAL_ALLOC_LIMIT_MB 0
#define MIN_ALLOC_LIMIT_MB 10

#define TRUE 1
#define FALSE 0

#define MAX_ENCODER_NAME_LENGTH 64 /* arbitrary limit to avoid runaway strcmp */

#define SUCCESS 0
#define ERR_OUT_OF_MEMORY -2
#define ERR_SYSCALL_FAILED -3
#define ERR_ENGINE_CALL_FAILED -4

/* These codes are returned in the length field of an str whose ptr is NULL */
#define ERR_NO_MATCH 0
#define ERR_NO_PATTERN 1
#define ERR_NO_TRACESTYLE 2	/* same as no encoder */
#define ERR_NO_FILE 3		/* no such file or directory */

#include <stdint.h>
#include <sys/param.h>		/* MAXPATHLEN */
#include "rpeg.h"	        /* "../../submodules/rosie-lpeg/src/rpeg.h" */

typedef struct rosie_string str;

typedef struct rosie_matchresult {
     str data;
     int leftover;
     int abend;
     int ttotal;
     int tmatch;
} match;

str rosie_new_string(byte_ptr msg, size_t len);
str *rosie_new_string_ptr(byte_ptr msg, size_t len);
void rosie_free_string(str s);
void rosie_free_string_ptr(str *s);

void *rosie_new(str *errors);
void rosie_finalize(void *L);
int rosie_setlibpath(void *L, char *newpath);
int rosie_set_alloc_limit(void *L, int newlimit);
int rosie_config(void *L, str *retvals);
int rosie_compile(void *L, str *expression, int *pat, str *errors);
int rosie_free_rplx(void *L, int pat);
int rosie_match(void *L, int pat, int start, char *encoder, str *input, match *match);
int rosie_matchfile(void *L, int pat, char *encoder, int wholefileflag,
		    char *infilename, char *outfilename, char *errfilename,
		    int *cin, int *cout, int *cerr,
		    str *err);
int rosie_trace(void *L, int pat, int start, char *trace_style, str *input, int *matched, str *trace);
int rosie_load(void *L, int *ok, str *src, str *pkgname, str *errors);
int rosie_import(void *L, int *ok, str *pkgname, str *as, str *errors);

/*

Administrative:
+  status:int, engine:void* = new(const char *name)
+  status:int = finalize(void *engine)
+  status:int, desc:string = config(void *engine)
*  status:int = setlibpath(void *engine, const char *libpath)
+  set soft memory limit to m MB, with optional logging of when it is hit
  logging level (to stderr)?
  clone an engine?  (to avoid setup cost; but cloned engine must be in new Lua state)


RPL:
+  status:int, pkgname:string, errors:strings = load(void *engine, const char *rpl)
+  status:int, pkgname:string, errors:strings = import(packageref, localname)
  status:int = undefine(id)
  test(rpl)?
  testfile(filename)?

Match/trace:
+  status:int, pat:int, errors:strings = compile(void *engine, const char *expression)
+  status:int = free_rplx(void *engine, int pat)
+  status:int = match(void *engine, int pat, int start, str *encoder,
		str *input, match *match);
+  status:int, tracestring:*buffer = trace(void *engine, int pat, buffer *input, int start, int encoder, int tracestyle)

  status:int, cin:int, cout:int, cerr:int, errors:strings =
    matchfile(void *engine, int pat, 
       const char *infilename, const char *outfilename, const char *errfilename, 
       int start, int encoder, int wholefile)

  status:int, cin:int, cout:int, cerr:int, errors:strings =
    tracefile(void *engine, void pat, 
       const char *infilename, const char *outfilename, const char *errfilename, 
       int start, int encoder, int readmethod, int tracestyle)

Debugging:
  status:int, desc:string = lookup(void *engine, const char *id)
  status:int, expr:string, errors:strings = expand(void *engine, const char *expr)
  status:int, descs:strings = list(void *engine, const char *localnamefilter, const char *packagenamefilter)

*/
