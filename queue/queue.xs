/* VMS::Queue - Get a list of Queues, or manage Queues
 *
 * Version: 0.01
 * Author:  Dan Sugalski <sugalsks@osshe.edu>
 * Revised: 05-Dec-1997
 *
 *
 * Revision History:
 *
 * 0.1  05-Dec-1997 Dan Sugalski <sugalskd@osshe>
 *      Snagged this source from VMS::Process, and gutted appropriately.
 *
 */

#ifdef __cplusplus
extern "C" {
#endif
#include <starlet.h>
#include <descrip.h>
#include <prvdef.h>
#include <jpidef.h>
#include <uaidef.h>
#include <ssdef.h>
#include <stsdef.h>
#include <statedef.h>
#include <prcdef.h>
#include <pcbdef.h>
#include <pscandef.h>
#include <quidef.h>  
#include <jbcmsgdef.h>
#include <sjcdef.h>
  
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#ifdef __cplusplus
}
#endif

typedef union {
  struct {short   buflen,          /* Length of output buffer */
                  itmcode;         /* Item code */
          void    *buffer;         /* Buffer address */
          long    itemflags;       /* Item flags */
        } BufferItem;  /* Layout of buffer $PROCESS_SCAN item-list elements */
                
  struct {short   buflen,          /* Length of output buffer */
                  itmcode;         /* Item code */
          long    itemvalue;       /* Value for this item */ 
          long    itemflags;       /* flags for this item */
        } LiteralItem;  /* Layout of literal $PROCESS_SCAN item-list */
                        /* elements */
  struct {short   buflen,          /* Length of output buffer */
                  itmcode;         /* Item code */
          void    *buffer;         /* Buffer address */
          void    *retlen;         /* Return length address */
        } TradItem;  /* Layout of 'traditional' item-list elements */
} ITMLST;

typedef struct {int sts;     /* Returned status */
                int unused;  /* Unused by us */
              } iosb;

typedef struct {char  *ItemName;         /* Name of the item we're getting */
                unsigned short *ReturnLength; /* Pointer to the return */
                                              /* buffer length */
                void  *ReturnBuffer;     /* generic pointer to the returned */
                                         /* data */
                int   ReturnType;        /* The type of data in the return */
                                         /* buffer */
                int   ItemListEntry;     /* Index of the entry in the item */
                                         /* list we passed to GETJPI */
              } FetchedItem; /* Use this keep track of the items in the */
                             /* 'grab everything' system call */ 

#define bit_test(HVPointer, BitToCheck, HVEntryName, EncodedMask) \
{ \
    if ((EncodedMask) & (BitToCheck)) \
    hv_store((HVPointer), (HVEntryName), strlen((HVEntryName)), &sv_yes, 0); \
    else \
    hv_store((HVPointer), (HVEntryName), strlen((HVEntryName)), &sv_no, 0);}   

#define IS_STRING 1
#define IS_LONGWORD 2
#define IS_QUADWORD 3
#define IS_WORD 4
#define IS_BYTE 5
#define IS_VMSDATE 6
#define IS_BITMAP 7   /* Each bit in the return value indicates something */
#define IS_ENUM 8     /* Each returned value has a name, and we ought to */
                      /* return the name instead of the value */

/* defines for input and/or output */
#define INPUT_INFO 1  /* The parameter's an input param for info reqests */
#define OUTPUT_INFO 2 /* The parameter's an output param for info requests */
#define INPUT_ACTION 4 /* The parameter's an input param for an action */
                       /* function */
#define OUTPUT_ACTION 8 /* The parameter's an output param for an action */
                        /* function */

/* defines to mark the system call parameters get passed to */
#define GETQUI_PARAM 1 /* The parameter goes to GETQUI */
#define SNDJBC_PARAM 2 /* The parameter goes to SNDJBC */

/* defines to mark the type of object (form, manager, queue, characteristic, */
/* or entry) the line's good for */
#define OBJECT_FORM 1
#define OBJECT_MANAGER 2
#define OBJECT_QUEUE 4
#define OBJECT_CHAR 8
#define OBJECT_ENTRY 16

/* Some defines to mark 'special' things about entries */
#define S_QUEUE_GENERIC  (1<<0)
#define S_QUEUE_BATCH    (1<<1)
#define S_QUEUE_PRINTER  (1<<2)
#define S_QUEUE_TERMINAL (1<<3)
#define S_QUEUE_OUTPUT   (S_QUEUE_PRINTER | S_QUEUE_TERMINAL)
#define S_QUEUE_ANY      (S_QUEUE_GENERIC | S_QUEUE_BATCH | S_QUEUE_PRINTER \
                          | S_QUEUE_TERMINAL)
#define S_ENTRY_BATCH    (1<<4)
#define S_ENTRY_PRINT    (1<<5)
#define S_ENTRY_DONE     (1<<6)
#define S_ENTRY_ANY      (S_ENTRY_BATCH | S_ENTRY_PRINT | S_ENTRY_DONE)
#define S_FORM_ANY       (1<<7)
#define S_ANY             -1


/* Macro to create an entry in the array that associates string names with */
/* their QUI$_ values, along with lots of other info for it */
#define GETQUI_ENTRY(a, b, c, d, e, f) \
        {#a, QUI$_##a, b, c, GETQUI_PARAM, \
           d, e, f}

#define QUI$M_ 0

struct MondoQueueInfoID {
  char *InfoName; /* Pointer to the item name */
  int  SysCallValue;  /* Value to use in the system call item list */
  int  BufferLen;     /* Length the return va buf needs to be. (no nul */
                      /* terminators, so must be careful with the return */
                      /* values. */
  int  ReturnType;    /* Type of data the item returns */
  int  SysCall;       /* What system call the item's to be used with */
  int  InOrOut;       /* Is it an input or an output parameter? */
  int  UseForObject;  /* Which object type this can be used for */
  int  SpecialFlags;  /* Subcategory for the item. (Used to restrict which */
                      /* items are being used for info calls, since bogus */
                      /* ones (like device name for batch queues) end up */
                      /* with invalid data) */
};

struct MondoQueueInfoID MondoQueueInfoList[] =
{
  GETQUI_ENTRY(ACCOUNT_NAME, 8, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(AFTER_TIME, 8, IS_VMSDATE, OUTPUT_INFO, OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(ASSIGNED_QUEUE_NAME, 31, IS_STRING, OUTPUT_INFO,
               OBJECT_ENTRY | OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(AUTOSTART_ON, 255, IS_STRING, OUTPUT_INFO, OBJECT_QUEUE,
               S_ANY),
  GETQUI_ENTRY(BASE_PRIORITY, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_QUEUE,
               S_ANY),
  GETQUI_ENTRY(CHARACTERISTIC_NAME, 31, IS_STRING, OUTPUT_INFO,
               OBJECT_CHAR, S_ANY),
  GETQUI_ENTRY(CHARACTERISTIC_NUMBER, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_CHAR, S_ANY),
/*  GETQUI_ENTRY(CHARACTERISTICS, 16, IS_BITMAP, OUTPUT_INFO,
               OBJECT_ENTRY | OBJECT_QUEUE, S_ANY),*/
  GETQUI_ENTRY(CHECKPOINT_DATA, 255, IS_STRING, OUTPUT_INFO,
               OBJECT_ENTRY, S_ENTRY_BATCH),
  GETQUI_ENTRY(CLI, 39, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_BATCH),
  GETQUI_ENTRY(COMPLETED_BLOCKS, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_ENTRY, S_QUEUE_OUTPUT),
  GETQUI_ENTRY(CONDITION_VECTOR, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(CPU_DEFAULT, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_QUEUE,
               S_QUEUE_BATCH),
  GETQUI_ENTRY(CPU_LIMIT, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_QUEUE | OBJECT_ENTRY,
               S_QUEUE_BATCH | S_ENTRY_BATCH),
  GETQUI_ENTRY(DEFAULT_FORM_NAME, 31, IS_STRING, OUTPUT_INFO,
               OBJECT_QUEUE, S_QUEUE_OUTPUT), 
  GETQUI_ENTRY(DEFAULT_FORM_STOCK, 31, IS_STRING, OUTPUT_INFO,
               OBJECT_QUEUE, S_QUEUE_OUTPUT), 
  GETQUI_ENTRY(DEVICE_NAME, 31, IS_STRING, OUTPUT_INFO, OBJECT_QUEUE,
               S_QUEUE_OUTPUT),
  GETQUI_ENTRY(ENTRY_NUMBER, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_ENTRY,
               S_ANY),
  GETQUI_ENTRY(EXECUTING_JOB_COUNT, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(FILE_COUNT, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_ENTRY,
               S_ANY),
  GETQUI_ENTRY(FORM_DESCRIPTION, 255, IS_STRING, OUTPUT_INFO, OBJECT_FORM,
               S_ANY),
  GETQUI_ENTRY(FORM_FLAGS, 4, IS_BITMAP, OUTPUT_INFO, OBJECT_FORM, S_ANY),
  GETQUI_ENTRY(FORM_LENGTH, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_FORM,
               S_ANY),
  GETQUI_ENTRY(FORM_MARGIN_BOTTOM, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_FORM, S_ANY),
  GETQUI_ENTRY(FORM_MARGIN_LEFT, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_FORM, S_ANY),
  GETQUI_ENTRY(FORM_MARGIN_RIGHT, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_FORM, S_ANY),
  GETQUI_ENTRY(FORM_MARGIN_TOP, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_FORM, S_ANY),
  GETQUI_ENTRY(FORM_NAME, 31, IS_STRING, OUTPUT_INFO,
               OBJECT_FORM | OBJECT_ENTRY | OBJECT_QUEUE,
               S_QUEUE_OUTPUT | S_ENTRY_PRINT | S_FORM_ANY),
  GETQUI_ENTRY(FORM_NUMBER, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_FORM, S_ANY),
  GETQUI_ENTRY(FORM_SETUP_MODULES, 256, IS_STRING, OUTPUT_INFO,
               OBJECT_FORM, S_ANY),
  GETQUI_ENTRY(FORM_STOCK, 31, IS_STRING, OUTPUT_INFO,
               OBJECT_FORM | OBJECT_ENTRY | OBJECT_QUEUE,
               S_QUEUE_OUTPUT | S_ENTRY_PRINT | S_FORM_ANY),
  GETQUI_ENTRY(FORM_WIDTH, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_FORM, S_ANY),
  GETQUI_ENTRY(GENERIC_TARGET, 3968, IS_STRING, OUTPUT_INFO, OBJECT_QUEUE,
               S_QUEUE_GENERIC),
  GETQUI_ENTRY(HOLDING_JOB_COUNT, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(JOB_COMPLETION_QUEUE, 31, IS_STRING, OUTPUT_INFO,
               OBJECT_ENTRY, S_ENTRY_DONE),
  GETQUI_ENTRY(JOB_COMPLETION_TIME, 8, IS_VMSDATE, OUTPUT_INFO,
               OBJECT_ENTRY, S_ENTRY_DONE),
  GETQUI_ENTRY(JOB_COPIES, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_PRINT),
  GETQUI_ENTRY(JOB_COPIES_DONE, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_PRINT),
  GETQUI_ENTRY(JOB_FLAGS, 4, IS_BITMAP, OUTPUT_INFO, OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(JOB_LIMIT, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(JOB_NAME, 39, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(JOB_PID, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_BATCH),
  GETQUI_ENTRY(JOB_RESET_MODULES, 256, IS_STRING, OUTPUT_INFO,
               OBJECT_QUEUE, S_QUEUE_OUTPUT),
  GETQUI_ENTRY(JOB_RETENTION_TIME, 8, IS_VMSDATE, OUTPUT_INFO,
               OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(JOB_SIZE, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_PRINT),
  GETQUI_ENTRY(JOB_SIZE_MAXIMUM, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_QUEUE,
               S_QUEUE_OUTPUT),
  GETQUI_ENTRY(JOB_SIZE_MINIMUM, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_QUEUE,
               S_QUEUE_OUTPUT),
  GETQUI_ENTRY(JOB_STATUS, 4, IS_BITMAP, OUTPUT_INFO, OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(LIBRARY_SPECIFICATION, 39, IS_STRING, OUTPUT_INFO,
               OBJECT_QUEUE, S_QUEUE_OUTPUT),
  GETQUI_ENTRY(LOG_QUEUE, 31, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_BATCH),
  GETQUI_ENTRY(LOG_SPECIFICATION, 39, IS_STRING, OUTPUT_INFO,
               OBJECT_ENTRY, S_ENTRY_BATCH),
  GETQUI_ENTRY(MANAGER_NAME, 31, IS_STRING, OUTPUT_INFO, OBJECT_MANAGER,
               S_ANY),
  GETQUI_ENTRY(MANAGER_NODES, 256, IS_STRING, OUTPUT_INFO, OBJECT_MANAGER,
               S_ANY),
  GETQUI_ENTRY(MANAGER_STATUS, 4, IS_BITMAP, OUTPUT_INFO, OBJECT_MANAGER,
               S_ANY),
  GETQUI_ENTRY(NOTE, 255, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(OPERATOR_REQUEST, 255, IS_STRING, OUTPUT_INFO,
               OBJECT_ENTRY, S_ENTRY_PRINT),
  GETQUI_ENTRY(OWNER_UIC, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(PARAMETER_1, 255, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_BATCH),
  GETQUI_ENTRY(PARAMETER_2, 255, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_BATCH),
  GETQUI_ENTRY(PARAMETER_3, 255, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_BATCH),
  GETQUI_ENTRY(PARAMETER_4, 255, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_BATCH),
  GETQUI_ENTRY(PARAMETER_5, 255, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_BATCH),
  GETQUI_ENTRY(PARAMETER_6, 255, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_BATCH),
  GETQUI_ENTRY(PARAMETER_7, 255, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_BATCH),
  GETQUI_ENTRY(PARAMETER_8, 255, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY,
               S_ENTRY_BATCH),
  GETQUI_ENTRY(PENDING_JOB_BLOCK_COUNT, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_QUEUE, S_QUEUE_OUTPUT),
  GETQUI_ENTRY(PENDING_JOB_COUNT, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(PENDING_JOB_REASON, 4, IS_BITMAP, OUTPUT_INFO,
               OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(PRIORITY, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(PROCESSOR, 39, IS_STRING, OUTPUT_INFO, OBJECT_QUEUE |
               OBJECT_ENTRY, S_QUEUE_OUTPUT | S_ENTRY_PRINT),
  GETQUI_ENTRY(PROTECTION, 4, IS_BITMAP, OUTPUT_INFO, OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(QUEUE_DESCRIPTION, 255, IS_STRING, OUTPUT_INFO,
               OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(QUEUE_DIRECTORY, 255, IS_STRING, OUTPUT_INFO,
               OBJECT_MANAGER, S_ANY),
  GETQUI_ENTRY(QUEUE_FLAGS, 4, IS_BITMAP, OUTPUT_INFO, OBJECT_ENTRY |
               OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(QUEUE_NAME, 31, IS_STRING, OUTPUT_INFO, OBJECT_QUEUE |
               OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(QUEUE_STATUS, 4, IS_BITMAP, OUTPUT_INFO, OBJECT_ENTRY |
               OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(REQUEUE_QUEUE_NAME, 31, IS_STRING, OUTPUT_INFO,
               OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(RESTART_QUEUE_NAME, 31, IS_STRING, OUTPUT_INFO,
               OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(RETAINED_JOB_COUNT, 4, IS_STRING, OUTPUT_INFO,
               OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(SCSNODE_NAME, 6, IS_STRING, OUTPUT_INFO, OBJECT_MANAGER,
               S_ANY),
/*  GETQUI_ENTRY(SEARCH_FLAGS, 4, IS_LONGWORD, INPUT_INFOETER, */
/*  OBJECT_QUEUE | OBJECT_MANAGER | OBJECT_FORM | OBJECT_CHAR | */
/*  OBJECT_ENTRY, S_ANY),*/
  GETQUI_ENTRY(SEARCH_JOB_NAME, 39, IS_STRING, INPUT_INFO, OBJECT_ENTRY,
               S_ANY),
  GETQUI_ENTRY(SEARCH_NAME, 31, IS_STRING, INPUT_INFO, OBJECT_QUEUE |
               OBJECT_MANAGER | OBJECT_FORM | OBJECT_CHAR,),
  GETQUI_ENTRY(SEARCH_NUMBER, 4, IS_LONGWORD, INPUT_INFO, OBJECT_CHAR |
               OBJECT_ENTRY | OBJECT_FORM, S_ANY),
  GETQUI_ENTRY(SEARCH_USERNAME, 12, IS_STRING, INPUT_INFO, OBJECT_ENTRY,
               S_ANY),
  GETQUI_ENTRY(SUBMISSION_TIME, 8, IS_VMSDATE, OUTPUT_INFO, OBJECT_ENTRY,
               S_ANY),
  GETQUI_ENTRY(TIMED_RELEASE_JOB_COUNT, 4, IS_LONGWORD, OUTPUT_INFO,
               OBJECT_QUEUE, S_ANY),
  GETQUI_ENTRY(UIC, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(USERNAME, 12, IS_STRING, OUTPUT_INFO, OBJECT_ENTRY, S_ANY),
  GETQUI_ENTRY(WSDEFAULT, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_ENTRY |
               OBJECT_QUEUE, S_ENTRY_BATCH | S_QUEUE_BATCH),
  GETQUI_ENTRY(WSEXTENT, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_ENTRY |
               OBJECT_QUEUE, S_ENTRY_BATCH | S_QUEUE_BATCH),
  GETQUI_ENTRY(WSQUOTA, 4, IS_LONGWORD, OUTPUT_INFO, OBJECT_ENTRY |
               OBJECT_QUEUE, S_ENTRY_BATCH | S_QUEUE_BATCH),
  {NULL, 0, 0, 0, 0, 0, 0, 0}
};

/* Some static info */
char *MonthNames[12] = {
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep",
  "Oct", "Nov", "Dec"} ;
int QueueItemCount = 0;
int EntryItemCount = 0;
int FormItemCount = 0;
int CharacteristicItemCount = 0;
int ManagerItemCount = 0;

/* Macro to fill in a 'traditional' item-list entry */
#define init_itemlist(ile, length, code, bufaddr, retlen_addr) \
{ \
    (ile)->TradItem.buflen = (length); \
    (ile)->TradItem.itmcode = (code); \
    (ile)->TradItem.buffer = (bufaddr); \
    (ile)->TradItem.retlen = (retlen_addr) ;}

void tote_up_items()
{
  /* Temp varaibles for all our statics, so we can be a little thread safer */
  int i, QueueItemTemp, EntryItemTemp, FormItemTemp, CharItemTemp,
  ManagerItemTemp;

  QueueItemTemp = 0;
  EntryItemTemp = 0;
  FormItemTemp = 0;
  CharItemTemp = 0;
  ManagerItemTemp = 0;
  
  for(i = 0; MondoQueueInfoList[i].InfoName; i++) {
    if (MondoQueueInfoList[i].UseForObject & OBJECT_QUEUE)
      QueueItemTemp++;
    if (MondoQueueInfoList[i].UseForObject & OBJECT_ENTRY)
      EntryItemTemp++;
    if (MondoQueueInfoList[i].UseForObject & OBJECT_FORM)
      FormItemTemp++;
    if (MondoQueueInfoList[i].UseForObject & OBJECT_CHAR)
      CharItemTemp++;
    if (MondoQueueInfoList[i].UseForObject & OBJECT_MANAGER)
      ManagerItemTemp++;
  }

  QueueItemCount = QueueItemTemp;
  EntryItemCount = EntryItemTemp;
  FormItemCount = FormItemTemp;
  CharacteristicItemCount = CharItemTemp;
  ManagerItemCount = ManagerItemTemp;
}

char *
decode_jbc(int JBC_To_Decode) {
  switch(JBC_To_Decode) {
  case JBC$_NORMAL:
    return("Normal");
  case JBC$_INVFUNCOD:
    return("Invalid function code");
  case JBC$_INVITMCOD:
    return("Invalid item list code");
  case JBC$_INVPARLEN:
    return("Invalid parameter length");
  case JBC$_INVQUENAM:
    return("Invalid Queue Name");
  case JBC$_JOBQUEDIS:
    return("Queue manager not started");
  case JBC$_MISREQPAR:
    return("Missing a required parameter");
  case JBC$_NOJOBCTX:
    return("No job context");
  case JBC$_NOMORECHAR:
    return("No more characteristics");
  case JBC$_NOMOREENT:
    return("No more entries");
  case JBC$_NOMOREFILE:
    return("No more files");
  case JBC$_NOMOREFORM:
    return("No more forms");
  case JBC$_NOMOREJOB:
    return("No more jobs");
  case JBC$_NOMOREQMGR:
    return("No more queue managers");
  case JBC$_NOMOREQUE:
    return("No more queues");
  case JBC$_NOQUECTX:
    return("No queue context");
  case JBC$_NOSUCHCHAR:
    return("No such characteristic");
  case JBC$_NOSUCHENT:
    return("No such entry");
  case JBC$_NOSUCHFILE:
    return("No such file");
  case JBC$_NOSUCHFORM:
    return("No such form");
  case JBC$_NOSUCHJOB:
    return("No such job");
  case JBC$_NOSUCHQMGR:
    return("No such queue manager");
  case JBC$_NOSUCHQUE:
    return("No such queue");
  case JBC$_AUTONOTSTART:
    return("Autostart queue, but no nodes with autostart started");
  case JBC$_BUFTOOSMALL:
    return("Buffer too small");
  case JBC$_DELACCESS:
    return("Can't delete file");
  case JBC$_DUPCHARNAME:
    return("Duplicate characteristic name");
  case JBC$_DUPCHARNUM:
    return("Duplicate characteritic number");
  case JBC$_DUPFORM:
    return("Duplicate form number");
  case JBC$_DUPFORMNAME:
    return("Duplicate form name");
  case JBC$_EMPTYJOB:
    return("No files specified for job");
  case JBC$_EXECUTING:
    return("Job is currently executing");
  case JBC$_INCDSTQUE:
    return("Destination queue type inconsistent with requested operation");
/*  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return("");
  case JBC$_:
    return(""); */
  default:
    return("Dunno");
  }
}

SV *
generic_bitmap_decode(char *InfoName, int BitmapValue)
{
  HV *AllPurposeHV;
  if (!strcmp(InfoName, "FORM_FLAGS")) {
    AllPurposeHV = newHV();
    bit_test(AllPurposeHV, QUI$M_FORM_SHEET_FEED, "FORM_SHEET_FEED",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_FORM_TRUNCATE, "FORM_TRUNCATE",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_FORM_WRAP, "FORM_WRAP", BitmapValue);
  } else {
  if (!strcmp(InfoName, "JOB_FLAGS")) {
    AllPurposeHV = newHV();
    bit_test(AllPurposeHV, QUI$M_JOB_CPU_LIMIT, "JOB_CPU_LIMIT", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_ERROR_RETENTION,
             "JOB_ERROR_RETENTION", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_FILE_BURST, "JOB_FILE_BURST",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_FILE_BURST_ONE, "JOB_FILE_BURST_ONE",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_FILE_FLAG, "JOB_FILE_FLAG",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_FILE_FLAG_ONE, "JOB_FILE_FLAG_ONE",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_FILE_PAGINATE, "JOB_FILE_PAGINATE",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_FILE_TRAILER, "JOB_FILE_TRAILER",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_FILE_TRAILER_ONE,
             "JOB_FILE_TRAILER_ONE", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_LOG_DELETE, "JOB_LOG_DELETE",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_LOG_NULL, "JOB_LOG_NULL", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_LOG_SPOOL, "JOB_LOG_SPOOL", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_LOWERCASE, "JOB_LOWERCASE", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_NOTIFY, "JOB_NOTIFY", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_RESTART, "JOB_RESTART", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_RETENTION, "JOB_RETENTION", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_WSDEFAULT, "JOB_WSDEFAULT", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_WSEXTENT, "JOB_WSEXTENT", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_WSQUOTA, "JOB_WSQUOTA", BitmapValue);
  } else {
  if (!strcmp(InfoName, "JOB_STATUS")) {
    AllPurposeHV = newHV();
    bit_test(AllPurposeHV, QUI$M_JOB_ABORTING, "JOB_ABORTING", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_EXECUTING, "JOB_EXECUTING", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_HOLDING, "JOB_HOLDING", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_INACCESSIBLE, "JOB_INACCESSIBLE",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_PENDING, "JOB_PENDING", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_REFUSED, "JOB_REFUSED", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_RETAINED, "JOB_RETAINED", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_STALLED, "JOB_STALLED", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_STARTING, "JOB_STARTING", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_SUSPENDED, "JOB_SUSPENDED", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_JOB_TIMED_RELEASE, "JOB_TIMED_RELEASE",
             BitmapValue);
  } else {
  if (!strcmp(InfoName, "MANAGER_FLAGS")) {
    AllPurposeHV = newHV();
    bit_test(AllPurposeHV, QUI$M_MANAGER_FAILOVER, "MANAGER_FAILOVER",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_MANAGER_RUNNING, "MANAGER_RUNNING",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_MANAGER_START_PENDING,
             "MANAGER_START_PENDING", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_MANAGER_STARTING, "MANAGER_STARTING",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_MANAGER_STOPPING, "MANAGER_STOPPING",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_MANAGER_STOPPED, "MANAGER_STOPPED",
             BitmapValue);
  } else {
  if (!strcmp(InfoName, "PENDING_JOB_REASON")) {
    AllPurposeHV = newHV();
    bit_test(AllPurposeHV, QUI$M_PEND_CHAR_MISMATCH, "PEND_CHAR_MISMATCH",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_PEND_JOB_SIZE_MAX, "PEND_JOB_SIZE_MAX",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_PEND_LOWERCASE_MISMATCH,
             "PEND_LOWERCASE_MISMATCH", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_PEND_NO_ACCESS, "PEND_NO_ACCESS",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_PEND_QUEUE_BUSY, "PEND_QUEUE_BUSY",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_PEND_QUEUE_STATE, "PEND_QUEUE_STATE",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_PEND_STOCK_MISMATCH,
             "PEND_STOCK_MISMATCH", BitmapValue);
  } else {
  if (!strcmp(InfoName, "QUEUE_FLAGS")) {
    AllPurposeHV = newHV();
    bit_test(AllPurposeHV, QUI$M_QUEUE_ACL_SPECIFIED,
             "QUEUE_ACL_SPECIFIED", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_AUTOSTART, "QUEUE_AUTOSTART",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_BATCH, "QUEUE_BATCH", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_CPU_DEFAULT, "QUEUE_CPU_DEFAULT",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_CPU_LIMIT, "QUEUE_CPU_LIMIT",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_FILE_BURST, "QUEUE_FILE_BURST",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_FILE_BURST_ONE,
             "QUEUE_FILE_BURST_ONE", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_FILE_FLAG, "QUEUE_FILE_FLAG",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_FILE_FLAG_ONE,
             "QUEUE_FILE_FLAG_ONE", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_FILE_PAGINATE,
             "QUEUE_FILE_PAGINATE", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_FILE_TRAILER, "QUEUE_FILE_TRAILER",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_FILE_TRAILER_ONE,
             "QUEUE_FILE_TRAILER_ONE", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_GENERIC, "QUEUE_GENERIC",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_GENERIC_SELECTION,
             "QUEUE_GENERIC_SELECTION", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_JOB_BURST, "QUEUE_JOB_BURST",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_JOB_FLAG, "QUEUE_JOB_FLAG",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_JOB_SIZE_SCHED,
             "QUEUE_JOB_SIZE_SCHED", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_JOB_TRAILER, "QUEUE_JOB_TRAILER",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_PRINTER, "QUEUE_PRINTER",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_RECORD_BLOCKING,
             "QUEUE_RECORD_BLOCKING", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_RETAIN_ALL, "QUEUE_RETAIN_ALL",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_RETAIN_ERROR, "QUEUE_RETAIN_ERROR",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_SWAP, "QUEUE_SWAP", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_TERMINAL, "QUEUE_TERMINAL",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_WSDEFAULT, "QUEUE_WSDEFAULT",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_WSEXTENT, "QUEUE_WSEXTENT",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_WSQUOTA, "QUEUE_WSQUOTA",
             BitmapValue);
  } else {
  if (!strcmp(InfoName, "QUEUE_STATUS")) {
    AllPurposeHV = newHV();
    bit_test(AllPurposeHV, QUI$M_QUEUE_ALIGNING, "QUEUE_ALIGNING",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_AUTOSTART_INACTIVE,
             "QUEUE_AUTOSTART_INACTIVE", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_AVAILABLE, "QUEUE_AVAILABLE",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_BUSY, "QUEUE_BUSY", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_CLOSED, "QUEUE_CLOSED",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_DISABLED, "QUEUE_DISABLED",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_IDLE, "QUEUE_IDLE", BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_LOWERCASE, "QUEUE_LOWERCASE",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_PAUSED, "QUEUE_PAUSED",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_PAUSING, "QUEUE_PAUSING",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_REMOTE, "QUEUE_REMOTE",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_RESETTING, "QUEUE_RESETTING",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_RESUMING, "QUEUE_RESUMING",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_SERVER, "QUEUE_SERVER",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_STALLED, "QUEUE_STALLED",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_STARTING, "QUEUE_STARTING",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_STOP_PENDING, "QUEUE_STOP_PENDING",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_STOPPED, "QUEUE_STOPPED",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_STOPPING, "QUEUE_STOPPING",
             BitmapValue);
    bit_test(AllPurposeHV, QUI$M_QUEUE_UNAVAILABLE, "QUEUE_UNAVAILABLE",
             BitmapValue);
  }}}}}}}
  if (AllPurposeHV) {
    return(newRV_noinc((SV *)AllPurposeHV));
  } else {
    return(&sv_undef);
  }
}

/* This routine runs through the MondoQueueInfoList array and pulls out all */
/* the things that match the object type passed */
SV *
generic_valid_properties(HV *HashToFill, int ObjectType)
{
  int i;
  SV *Input_InfoSV, *Output_InfoSV, *Input_ActionSV, *Output_ActionSV;
  HV *ResultHV;
  
  /* Create the SVs for input, output and in/out returns */
  Input_InfoSV = sv_2mortal(newSVpv("INPUT_INFO", 0));
  Output_InfoSV = sv_2mortal(newSVpv("OUTPUT_INFO", 0));
  Input_ActionSV = sv_2mortal(newSVpv("INPUT_ACTION", 0));
  Output_ActionSV = sv_2mortal(newSVpv("OUTPUT_ACTION", 0));
  
  for(i=0; MondoQueueInfoList[i].InfoName; i++) {
    if (MondoQueueInfoList[i].UseForObject & ObjectType) {
      
      /* Allocate a new AV to hold our results */
      ResultHV = newHV();
      
      /* Run through the options */
      if (MondoQueueInfoList[i].InOrOut & INPUT_INFO)
        hv_store_ent(HashToFill, Input_InfoSV, &sv_yes, 0);
      else
        hv_store_ent(HashToFill, Input_InfoSV, &sv_no, 0);

      if (MondoQueueInfoList[i].InOrOut & OUTPUT_INFO)
        hv_store_ent(HashToFill, Output_InfoSV, &sv_yes, 0);
      else
        hv_store_ent(HashToFill, Output_InfoSV, &sv_no, 0);

      if (MondoQueueInfoList[i].InOrOut & INPUT_ACTION)
        hv_store_ent(HashToFill, Input_ActionSV, &sv_yes, 0);
      else
        hv_store_ent(HashToFill, Input_ActionSV, &sv_no, 0);

      if (MondoQueueInfoList[i].InOrOut & OUTPUT_ACTION)
        hv_store_ent(HashToFill, Output_ActionSV, &sv_yes, 0);
      else
        hv_store_ent(HashToFill, Output_ActionSV, &sv_no, 0);
      
      hv_store(HashToFill, MondoQueueInfoList[i].InfoName,
               strlen(MondoQueueInfoList[i].InfoName),
               (SV *)newRV_noinc((SV *)ResultHV), 0);
    }
  }

  return (SV *)HashToFill;
}

/* This routine gets passed a pre-cleared array that's big enough for all */
/* the pieces we'll fill in, and that has the input parameter stuck in */
/* entry 0. We allocate the memory and fill in the rest of the array, and */
/* pass back a hash that has all the return results in it. */
SV *
generic_getqui_call(ITMLST *ListOItems, int ObjectType, int InfoCount,
                    short QUIFunction, int SpecialFlags)
{
  FetchedItem *OurDataList;
  unsigned short *ReturnLengths;
  int i, LocalIndex;
  iosb GenericIOSB;
  int status;
  int ContextStream = 0;
  HV *AllPurposeHV;
  unsigned short ReturnedTime[7];
  char AsciiTime[100];
  char QuadWordString[65];
  long *TempLongPointer;
  __int64 *TempQuadPointer;
  char *TempStringBuffer;
  
  LocalIndex = 0;
  
  /* Allocate the local tracking array */
  OurDataList = malloc(sizeof(FetchedItem) * InfoCount);
  memset(OurDataList, 0, sizeof(FetchedItem) * InfoCount);
  
  /* We also need room for the buffer lengths */
  ReturnLengths = malloc(sizeof(short) * InfoCount);
  memset(ReturnLengths, 0, sizeof(short) * InfoCount);
  
  
  /* Fill in the item list and the tracking list */
  for (i = 0; MondoQueueInfoList[i].InfoName; i++) {
    if ((MondoQueueInfoList[i].UseForObject & ObjectType) &&
        (MondoQueueInfoList[i].SpecialFlags & SpecialFlags) &&
        (MondoQueueInfoList[i].InOrOut & OUTPUT_INFO)) {
      /* Increment the local index */
      LocalIndex++;
      
      /* Allocate the return data buffer and zero it. Can be oddly
         sized, so we use the system malloc instead of New */
      OurDataList[LocalIndex - 1].ReturnBuffer =
        malloc(MondoQueueInfoList[i].BufferLen);
      memset(OurDataList[LocalIndex - 1].ReturnBuffer, 0,
             MondoQueueInfoList[i].BufferLen); 

      /* Note some important stuff (like what we're doing) in our local */
      /* tracking array */
      OurDataList[LocalIndex - 1].ItemName =
        MondoQueueInfoList[i].InfoName;
      OurDataList[LocalIndex - 1].ReturnLength = &ReturnLengths[LocalIndex
                                                                - 1];
      OurDataList[LocalIndex - 1].ReturnType =
        MondoQueueInfoList[i].ReturnType;
      OurDataList[LocalIndex - 1].ItemListEntry = i;
      
      /* Fill in the item list */
      init_itemlist(&ListOItems[LocalIndex], MondoQueueInfoList[i].BufferLen,
                    MondoQueueInfoList[i].SysCallValue,
                    OurDataList[LocalIndex - 1].ReturnBuffer,
                    &ReturnLengths[LocalIndex - 1]);
    }
  }
  
  /* Make the GETQUIW call */
  status = sys$getquiw(NULL, QUIFunction, ContextStream, ListOItems,
                       &GenericIOSB, NULL, NULL);

  /* Did it go OK? */
  if ((status == SS$_NORMAL) && (GenericIOSB.sts == JBC$_NORMAL)) {
    /* Looks like it */
    AllPurposeHV = newHV();
    for (i = 0; i < LocalIndex; i++) {
      switch(OurDataList[i].ReturnType) {
      case IS_STRING:
        /* copy the return string into a temporary buffer with C's string */
        /* handling routines. For some reason $GETQUI returns values with */
        /* embedded nulls and bogus lengths, which is really */
        /* strange. Anyway, this is a cheap way to see how long the */
        /* string is without doing a strlen(), which might fall off the */
        /* end of the world */
        TempStringBuffer = malloc(*(OurDataList[i].ReturnLength) + 1);
        memset(TempStringBuffer, 0, *(OurDataList[i].ReturnLength) + 1);
        strncpy(TempStringBuffer, OurDataList[i].ReturnBuffer,
                *(OurDataList[i].ReturnLength));
        if (strlen(TempStringBuffer) < *(OurDataList[i].ReturnLength))
          *(OurDataList[i].ReturnLength) = strlen(TempStringBuffer);
        free(TempStringBuffer);
        /* Check to make sure we got something back, otherwise set the */
        /* value to undef */
        if (*(OurDataList[i].ReturnLength)) {
          hv_store(AllPurposeHV, OurDataList[i].ItemName,
                   strlen(OurDataList[i].ItemName),
                   newSVpv(OurDataList[i].ReturnBuffer,
                           *OurDataList[i].ReturnLength), 0);
        } else {
          hv_store(AllPurposeHV, OurDataList[i].ItemName,
                   strlen(OurDataList[i].ItemName),
                   &sv_undef, 0);
        }
        break;
      case IS_VMSDATE:
        sys$numtim(ReturnedTime, OurDataList[i].ReturnBuffer);
        sprintf(AsciiTime, "%02hi-%s-%hi %02hi:%02hi:%02hi.%hi",
                ReturnedTime[2], MonthNames[ReturnedTime[1] - 1],
                ReturnedTime[0], ReturnedTime[3], ReturnedTime[4],
                ReturnedTime[5], ReturnedTime[6]);
        hv_store(AllPurposeHV, OurDataList[i].ItemName,
                 strlen(OurDataList[i].ItemName),
                 newSVpv(AsciiTime, 0), 0);
        break;
        /* No enums for now, so comment this out */
        /*
      case IS_ENUM:
        TempLongPointer = OurDataList[i].ReturnBuffer;
        hv_store(AllPurposeHV, OurDataList[i].ItemName,
                 strlen(OurDataList[i].ItemName),
                 enum_name(MondoQueueInfoList[i].SysCallValue,
                           *TempLongPointer), 0);
        break;
        */
      case IS_BITMAP:
      case IS_LONGWORD:
        TempLongPointer = OurDataList[i].ReturnBuffer;
        hv_store(AllPurposeHV, OurDataList[i].ItemName,
                 strlen(OurDataList[i].ItemName),
                 newSViv(*TempLongPointer),
                 0);
        break;
      case IS_QUADWORD:
        TempQuadPointer = OurDataList[i].ReturnBuffer;
        sprintf(QuadWordString, "%llu", *TempQuadPointer);
        hv_store(AllPurposeHV, OurDataList[i].ItemName,
                 strlen(OurDataList[i].ItemName),
                 newSVpv(QuadWordString, 0), 0);
        break;
        
      }
    }
    return(newRV_noinc((SV *) AllPurposeHV));
  } else {
    /* I think we failed */
    SETERRNO(EVMSERR, status);
    return (&sv_undef);
  }
  
  /* Free up our allocated memory */
  for(i = 0; i < InfoCount; i++) {
    free(OurDataList[i].ReturnBuffer);
  }
  free(OurDataList);
  free(ReturnLengths);
}


MODULE = VMS::Queue		PACKAGE = VMS::Queue		

void
queue_list(...)
   PPCODE:
{
  /* variables */
  ITMLST QueueScanItemList[99]; /* Yes, this should be a pointer and the */
                                /* memory should be dynamically */
                                /* allocated. When I try, wacky things */
                                /* happen, so we fall back to this hack */
  int status;
  unsigned int QueueContext = -1;
  char WildcardSearchName[] = "*";
  short WildcardSearchNameReturnLength; /* Shouldn't ever need this, but */
                                        /* just in case... */
  char QueueNameBuffer[255];
  short QueueNameBufferReturnLength;
  iosb QueueIOSB;

  /* First, zero out as much of the array as we're using */
  Zero(&QueueScanItemList, items == 0 ? 3: items, ITMLST);
  
  /* Did they pass us anything? */
  if (items == 0) {

    /* Fill in the item list. Right now we just return all the queues we */
    /* can get our hands on */
    init_itemlist(&QueueScanItemList[0], 1, QUI$_SEARCH_NAME,
                  WildcardSearchName, &WildcardSearchNameReturnLength);
    init_itemlist(&QueueScanItemList[1], 255, QUI$_QUEUE_NAME,
                  QueueNameBuffer, &QueueNameBufferReturnLength);
  } else {
  }
  
  /* Call $GETQUI in wildcard mode */
  status = sys$getquiw(0, QUI$_DISPLAY_QUEUE, &QueueContext,
                       QueueScanItemList, &QueueIOSB, NULL, 0);
  /* We just loop as long as things are OK */
  while ((status == SS$_NORMAL) && (QueueIOSB.sts == JBC$_NORMAL)) {
    /* Stick the returned value on the return stack */
    XPUSHs(sv_2mortal(newSVpv(QueueNameBuffer,
                              QueueNameBufferReturnLength)));
    
    /* Call again */
    status = sys$getquiw(0, QUI$_DISPLAY_QUEUE, &QueueContext,
                         QueueScanItemList, &QueueIOSB, NULL, 0);
  }
}

void
entry_list(...)
   PPCODE:
{
  /* This routine is fairly annoying, as we have to iterate through each */
  /* queue, then for each job in that queue. It'd be much nicer if we could */
  /* just go through all the entries or jobs by themselves, but we */
  /* can't. :( */

  /* variables for the main queue scan */
  ITMLST QueueScanItemList[99]; /* Yes, this should be a pointer and the */
                                /* memory should be dynamically */
                                /* allocated. When I try, wacky things */
                                /* happen, so we fall back to this hack */
  int QueueStatus;
  unsigned int QueueContext = -1;
  char WildcardSearchName[] = "*";
  short WildcardSearchNameReturnLength; /* Shouldn't ever need this, but */
                                        /* just in case... */
  char QueueNameBuffer[255];
  short QueueNameBufferReturnLength;
  iosb QueueIOSB;

  /* variables for the entries*/
  ITMLST EntryScanItemList[99]; /* Yes, this should be a pointer and the */
                                /* memory should be dynamically */
                                /* allocated. When I try, wacky things */
                                /* happen, so we fall back to this hack */
  int EntryStatus;
  int WildcardSearchFlags = QUI$M_SEARCH_ALL_JOBS;
  short WildcardSearchFlagsReturnLength; /* Shouldn't ever need this, but */
                                        /* just in case... */
  long EntryNumber;
  short EntryNumberReturnLength;
  char WildcardUserName[] = "*";
  short WildcardUserNameReturnLength;
  iosb EntryIOSB;


  /* First, zero out as much of the arrays as we're using */
  Zero(&QueueScanItemList, items == 0 ? 3: items, ITMLST);
  Zero(&EntryScanItemList, items == 0 ? 3: items, ITMLST);  
  
  /* Did they pass us anything? */
  if (items == 0) {

    /* Fill in the 'loop through the queues' item list */
    init_itemlist(&QueueScanItemList[0], 1, QUI$_SEARCH_NAME,
                  WildcardSearchName, &WildcardSearchNameReturnLength);
    init_itemlist(&QueueScanItemList[1], 255, QUI$_QUEUE_NAME,
                  QueueNameBuffer, &QueueNameBufferReturnLength);
  } else {
  }
  
  /* Did they pass us anything? */
  if (items == 0) {

    /* Fill in the item list. Right now we just return all the entries we */
    /* can get our hands on */
    init_itemlist(&EntryScanItemList[0], sizeof(WildcardSearchFlags),
                  QUI$_SEARCH_FLAGS, &WildcardSearchFlags,
                  &WildcardSearchFlagsReturnLength);
    init_itemlist(&EntryScanItemList[1], sizeof(EntryNumber),
                  QUI$_ENTRY_NUMBER, &EntryNumber,
                  &EntryNumberReturnLength);
  } else {
  }
  
  /* Call $GETQUI in wildcard mode for the queues */
  QueueStatus = sys$getquiw(0, QUI$_DISPLAY_QUEUE, &QueueContext,
                            QueueScanItemList, &QueueIOSB, NULL, 0);
    
  /* We just loop as long as things are OK */
  while ((QueueStatus == SS$_NORMAL) && (QueueIOSB.sts == JBC$_NORMAL)) {
    /* If we're in here, then we must have a queue. Try processing the */
    /* jobs for the queue */
    EntryStatus = sys$getquiw(0, QUI$_DISPLAY_JOB, &QueueContext,
                              EntryScanItemList, &EntryIOSB, NULL, 0);
    
    /* We just loop as long as things are OK */
    while ((EntryStatus == SS$_NORMAL) && (EntryIOSB.sts == JBC$_NORMAL)) {
      /* Stick the returned value on the return stack */
      XPUSHs(sv_2mortal(newSViv(EntryNumber)));
      
      /* Call again */
      EntryStatus = sys$getquiw(0, QUI$_DISPLAY_JOB, &QueueContext,
                           EntryScanItemList, &EntryIOSB, NULL, 0);
    }
    
    /* Call again */
    QueueStatus = sys$getquiw(0, QUI$_DISPLAY_QUEUE, &QueueContext,
                         QueueScanItemList, &QueueIOSB, NULL, 0);
    
  }
}

void
form_list(...)
   PPCODE:
{
  /* variables */
  ITMLST FormScanItemList[99]; /* Yes, this should be a pointer and the */
                                /* memory should be dynamically */
                                /* allocated. When I try, wacky things */
                                /* happen, so we fall back to this hack */
  int status;
  unsigned int FormContext = -1;
  char WildcardSearchName[] = "*";
  short WildcardSearchNameReturnLength; /* Shouldn't ever need this, but */
                                        /* just in case... */
  int FormNumberBuffer;
  short FormNumberBufferReturnLength;
  iosb FormIOSB;

  /* First, zero out as much of the array as we're using */
  Zero(&FormScanItemList, items == 0 ? 3: items, ITMLST);
  
  /* Did they pass us anything? */
  if (items == 0) {

    /* Fill in the item list. Right now we just return all the forms we */
    /* can get our hands on */
    init_itemlist(&FormScanItemList[0], 1, QUI$_SEARCH_NAME,
                  WildcardSearchName, &WildcardSearchNameReturnLength);
    init_itemlist(&FormScanItemList[1], sizeof(FormNumberBuffer),
                  QUI$_FORM_NUMBER, &FormNumberBuffer,
                  &FormNumberBufferReturnLength);
  } else {
  }
  
  /* Call $GETQUI in wildcard mode */
  status = sys$getquiw(0, QUI$_DISPLAY_FORM, &FormContext,
                       FormScanItemList, &FormIOSB, NULL, 0);
  /* We just loop as long as things are OK */
  while ((status == SS$_NORMAL) && (FormIOSB.sts == JBC$_NORMAL)) {
    /* Stick the returned value on the return stack */
    XPUSHs(sv_2mortal(newSViv(FormNumberBuffer)));
    
    /* Call again */
    status = sys$getquiw(0, QUI$_DISPLAY_FORM, &FormContext,
                         FormScanItemList, &FormIOSB, NULL, 0);
  }
}

void
characteristic_list(...)
   PPCODE:
{
  /* variables */
  ITMLST CharacteristicScanItemList[99]; /* Yes, this should be a pointer and the */
                                /* memory should be dynamically */
                                /* allocated. When I try, wacky things */
                                /* happen, so we fall back to this hack */
  int status;
  unsigned int CharacteristicContext = -1;
  char WildcardSearchName[] = "*";
  short WildcardSearchNameReturnLength; /* Shouldn't ever need this, but */
                                        /* just in case... */
  int CharacteristicNumberBuffer;
  short CharacteristicNumberBufferReturnLength;
  iosb CharacteristicIOSB;

  /* First, zero out as much of the array as we're using */
  Zero(&CharacteristicScanItemList, items == 0 ? 3: items, ITMLST);
  
  /* Did they pass us anything? */
  if (items == 0) {

    /* Fill in the item list. Right now we just return all the */
    /* characteristics we can get our hands on */
    init_itemlist(&CharacteristicScanItemList[0], 1, QUI$_SEARCH_NAME,
                  WildcardSearchName, &WildcardSearchNameReturnLength);
    init_itemlist(&CharacteristicScanItemList[1], 255,
                  QUI$_CHARACTERISTIC_NUMBER, &CharacteristicNumberBuffer,
                  &CharacteristicNumberBufferReturnLength);
  } else {
  }
  
  /* Call $GETQUI in wildcard mode */
  status = sys$getquiw(0, QUI$_DISPLAY_CHARACTERISTIC,
                       &CharacteristicContext, CharacteristicScanItemList,
                       &CharacteristicIOSB, NULL, 0);
  /* We just loop as long as things are OK */
  while ((status == SS$_NORMAL) && (CharacteristicIOSB.sts == JBC$_NORMAL)) {
    /* Stick the returned value on the return stack */
    XPUSHs(sv_2mortal(newSViv(CharacteristicNumberBuffer)));
    
    /* Call again */
    status = sys$getquiw(0, QUI$_DISPLAY_CHARACTERISTIC,
                         &CharacteristicContext,
                         CharacteristicScanItemList, &CharacteristicIOSB,
                         NULL, 0);
  }
}


void
manager_list(...)
   PPCODE:
{
  /* variables */
  ITMLST ManagerScanItemList[99]; /* Yes, this should be a pointer and the */
                                /* memory should be dynamically */
                                /* allocated. When I try, wacky things */
                                /* happen, so we fall back to this hack */
  int status;
  unsigned int ManagerContext = -1;
  char WildcardSearchName[] = "*";
  short WildcardSearchNameReturnLength; /* Shouldn't ever need this, but */
                                        /* just in case... */
  char ManagerNameBuffer[255];
  short ManagerNameBufferReturnLength;
  iosb ManagerIOSB;

  /* First, zero out as much of the array as we're using */
  Zero(&ManagerScanItemList, items == 0 ? 3: items, ITMLST);
  
  /* Did they pass us anything? */
  if (items == 0) {

    /* Fill in the item list. Right now we just return all the managers we */
    /* can get our hands on */
    init_itemlist(&ManagerScanItemList[0], 1, QUI$_SEARCH_NAME,
                  WildcardSearchName, &WildcardSearchNameReturnLength);
    init_itemlist(&ManagerScanItemList[1], 255, QUI$_MANAGER_NAME,
                  ManagerNameBuffer, &ManagerNameBufferReturnLength);
  } else {
  }
  
  /* Call $GETQUI in wildcard mode */
  status = sys$getquiw(0, QUI$_DISPLAY_MANAGER, &ManagerContext,
                       ManagerScanItemList, &ManagerIOSB, NULL, 0);
  /* We just loop as long as things are OK */
  while ((status == SS$_NORMAL) && (ManagerIOSB.sts == JBC$_NORMAL)) {
    /* Stick the returned value on the return stack */
    XPUSHs(sv_2mortal(newSVpv(ManagerNameBuffer,
                              ManagerNameBufferReturnLength)));
    
    /* Call again */
    status = sys$getquiw(0, QUI$_DISPLAY_MANAGER, &ManagerContext,
                         ManagerScanItemList, &ManagerIOSB, NULL, 0);
  }
}


void
queue_info(QueueName)
     char *QueueName
   CODE:
{
  
  ITMLST *ListOItems;
  unsigned short ReturnBufferLength = 0;
  unsigned int QueueFlags;
  unsigned short ReturnFlagsLength;
  unsigned int Status;
  iosb QueueIOSB;
  unsigned int SubType;
  
  /* If we've not gotten the count of items, go get it now */
  if (QueueItemCount == 0) {
    tote_up_items();
  }
     
  /* We need room for our item list */
  ListOItems = malloc(sizeof(ITMLST) * (QueueItemCount + 1));
  memset(ListOItems, 0, sizeof(ITMLST) * (QueueItemCount + 1));

  /* First, do a quick call to get the queue flags. We need 'em so we can */
  /* figure out what special flag we need to pass to the generic fetcher */
  init_itemlist(&ListOItems[0], strlen(QueueName), QUI$_SEARCH_NAME, QueueName,
                &ReturnBufferLength); 
  init_itemlist(&ListOItems[1], sizeof(QueueFlags), QUI$_QUEUE_FLAGS,
                &QueueFlags, &ReturnFlagsLength);

  Status = sys$getquiw(NULL, QUI$_DISPLAY_QUEUE, NULL, ListOItems,
                       &QueueIOSB, NULL, NULL);
  if (Status == SS$_NORMAL) {
    /* First, figure out the flag */
    SubType = 0;
    if (QueueFlags & QUI$M_QUEUE_BATCH)
      SubType |= S_QUEUE_BATCH;
    if (QueueFlags & QUI$M_QUEUE_GENERIC)
      SubType |= S_QUEUE_GENERIC;
    if (QueueFlags & QUI$M_QUEUE_PRINTER)
      SubType |= S_QUEUE_PRINTER;
    if (QueueFlags & QUI$M_QUEUE_TERMINAL)
      SubType |= S_QUEUE_TERMINAL;

    
    /* Make the call to the generic fetcher and make it the return */
    /* value. We don't need to go messing with the item list, since what we */
    /* used for the last call is OK to pass along to this one. */
    ST(0) = generic_getqui_call(ListOItems, OBJECT_QUEUE, QueueItemCount,
                                QUI$_DISPLAY_QUEUE, SubType);
  } else {
    ST(0) = &sv_undef;
    SETERRNO(EVMSERR, Status);
  }
      
  /* Give back the allocated item list memory */
  free(ListOItems);
}

void
entry_info(EntryNumber)
     int EntryNumber
   CODE:
{
  
  ITMLST *ListOItems;
  unsigned short ReturnBufferLength = 0;
  unsigned int QueueFlags;
  unsigned short QueueFlagsLength;
  unsigned int EntryFlags;
  unsigned short EntryFlagsLength;
  unsigned int Status;
  iosb EntryIOSB;
  unsigned int SubType;
  
  /* If we've not gotten the count of items, go get it now */
  if (EntryItemCount == 0) {
    tote_up_items();
  }

  /* We need room for our item list */
  ListOItems = malloc(sizeof(ITMLST) * (EntryItemCount + 1));
  memset(ListOItems, 0, sizeof(ITMLST) * (EntryItemCount + 1));

  /* First, do a quick call to get the queue flags. We need 'em so we can */
  /* figure out what special flag we need to pass to the generic fetcher */
  init_itemlist(&ListOItems[0], sizeof(EntryNumber), QUI$_SEARCH_NUMBER,
                &EntryNumber, &ReturnBufferLength); 
  init_itemlist(&ListOItems[1], sizeof(QueueFlags), QUI$_QUEUE_FLAGS,
                &QueueFlags, &QueueFlagsLength);
  init_itemlist(&ListOItems[2], sizeof(EntryFlags), QUI$_JOB_STATUS,
                &EntryFlags, &EntryFlagsLength);
  
  
  Status = sys$getquiw(NULL, QUI$_DISPLAY_ENTRY, NULL, ListOItems,
                       &EntryIOSB, NULL, NULL);
  if (Status == SS$_NORMAL) {
    /* The flags tell us what queue type we're on, so we can figure out what */
    /* type of entry we are */
    SubType = 0;
    if (QueueFlags & QUI$M_QUEUE_BATCH)
      SubType |= S_ENTRY_BATCH;
    if ((QueueFlags & QUI$M_QUEUE_GENERIC) && !(QueueFlags &
                                                QUI$M_QUEUE_BATCH))
      SubType |= S_ENTRY_PRINT;
    if (QueueFlags & QUI$M_QUEUE_PRINTER)
      SubType |= S_ENTRY_PRINT;
    if (QueueFlags & QUI$M_QUEUE_TERMINAL)
      SubType |= S_ENTRY_PRINT;
    if (EntryFlags & QUI$M_JOB_RETAINED)
      SubType |= S_ENTRY_DONE;

    /* Make the call to the generic fetcher and make it the return */
    /* value. We don't need to go messing with the item list, since what we */
    /* used for the last call is OK to pass along to this one. */
    ST(0) = generic_getqui_call(ListOItems, OBJECT_ENTRY, EntryItemCount,
                                QUI$_DISPLAY_ENTRY, SubType);
  } else {
    ST(0) = &sv_undef;
    SETERRNO(EVMSERR, Status);
  }
      
  /* Give back the allocated item list memory */
  free(ListOItems);
}

void
form_info(FormNumber)
     int FormNumber
   CODE:
{
  
  ITMLST *ListOItems;
  unsigned short ReturnBufferLength = 0;
  unsigned int SubType;
  
  /* If we've not gotten the count of items, go get it now */
  if (FormItemCount == 0) {
    tote_up_items();
  }

  /* We need room for our item list */
  ListOItems = malloc(sizeof(ITMLST) * (FormItemCount + 1));
  memset(ListOItems, 0, sizeof(ITMLST) * (FormItemCount + 1));

  /* First, do a quick call to get the queue flags. We need 'em so we can */
  /* figure out what special flag we need to pass to the generic fetcher */
  init_itemlist(&ListOItems[0], sizeof(FormNumber), QUI$_SEARCH_NUMBER,
                &FormNumber, &ReturnBufferLength); 

  /* No special bits for forms, so get everything */
  SubType = S_ANY;

  /* Make the call to the generic fetcher and make it the return */
  /* value. We don't need to go messing with the item list, since what we */
  /* used for the last call is OK to pass along to this one. */
  ST(0) = generic_getqui_call(ListOItems, OBJECT_FORM, FormItemCount,
                              QUI$_DISPLAY_FORM, SubType);
      
  /* Give back the allocated item list memory */
  free(ListOItems);
}

void
manager_info(ManagerName)
     char *ManagerName
   CODE:
{
  
  ITMLST *ListOItems;
  unsigned short ReturnBufferLength = 0;
  unsigned int SubType;
  
  /* If we've not gotten the count of items, go get it now */
  if (ManagerItemCount == 0) {
    tote_up_items();
  }
     
  /* We need room for our item list */
  ListOItems = malloc(sizeof(ITMLST) * (ManagerItemCount + 1));
  memset(ListOItems, 0, sizeof(ITMLST) * (ManagerItemCount + 1));

  /* First, do a quick call to get the queue flags. We need 'em so we can */
  /* figure out what special flag we need to pass to the generic fetcher */
  init_itemlist(&ListOItems[0], strlen(ManagerName), QUI$_SEARCH_NAME,
                ManagerName, &ReturnBufferLength);

  /* No subtype--we just go for it */
  SubType = S_ANY;

  /* Make the call to the generic fetcher and make it the return */
  /* value. We don't need to go messing with the item list, since what we */
  /* used for the last call is OK to pass along to this one. */
  ST(0) = generic_getqui_call(ListOItems, OBJECT_MANAGER, ManagerItemCount,
                              QUI$_DISPLAY_MANAGER, SubType);
      
  /* Give back the allocated item list memory */
  free(ListOItems);
}

SV *
queue_properties()
   CODE:
{
  HV *QueuePropHV;
  QueuePropHV = newHV();
  ST(0) = newRV_noinc(generic_valid_properties(QueuePropHV, OBJECT_QUEUE));
}

SV *
entry_properties()
   CODE:
{
  HV *EntryPropHV;
  EntryPropHV = newHV();
  ST(0) = newRV_noinc(generic_valid_properties(EntryPropHV, OBJECT_ENTRY));
}

SV *
form_properties()
   CODE:
{
  HV *FormPropHV;
  FormPropHV = newHV();
  ST(0) = newRV_noinc(generic_valid_properties(FormPropHV, OBJECT_FORM));
}

SV *
characteristic_properties()
   CODE:
{
  HV *CharacteristicPropHV;
  CharacteristicPropHV = newHV();
  ST(0) = newRV_noinc(generic_valid_properties(CharacteristicPropHV,
                                               OBJECT_CHAR));
}

SV *
manager_properties()
   CODE:
{
  HV *ManagerPropHV;
  ManagerPropHV = newHV();
  ST(0) = newRV_noinc(generic_valid_properties(ManagerPropHV,
                                               OBJECT_MANAGER));
}

SV *
queue_bitmap_decode(InfoName, BitmapValue)
     char *InfoName
     int BitmapValue
   CODE:
{
  ST(0) = generic_bitmap_decode(InfoName, BitmapValue);
}

SV *
entry_bitmap_decode(InfoName, BitmapValue)
     char *InfoName
     int BitmapValue
   CODE:
{
  ST(0) = generic_bitmap_decode(InfoName, BitmapValue);
}

SV *
form_bitmap_decode(InfoName, BitmapValue)
     char *InfoName
     int BitmapValue
   CODE:
{
  ST(0) = generic_bitmap_decode(InfoName, BitmapValue);
}

SV *
characteristic_bitmap_decode(InfoName, BitmapValue)
     char *InfoName
     int BitmapValue
   CODE:
{
  ST(0) = generic_bitmap_decode(InfoName, BitmapValue);
}

SV *
manager_bitmap_decode(InfoName, BitmapValue)
     char *InfoName
     int BitmapValue
   CODE:
{
  ST(0) = generic_bitmap_decode(InfoName, BitmapValue);
}

SV *
delete_entry(EntryNumber)
     int EntryNumber
   CODE:
{
  ITMLST NukeItemList[2];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 2);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], sizeof(EntryNumber), SJC$_ENTRY_NUMBER,
                &EntryNumber, &ReturnLength);

  /* make the call */
  Status = sys$sndjbcw(0, SJC$_DELETE_JOB, 0, NukeItemList, &KillIOSB,
                       NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

  
SV *
hold_entry(EntryNumber)
     int EntryNumber
   CODE:
{
  ITMLST NukeItemList[3];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 3);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], sizeof(EntryNumber), SJC$_ENTRY_NUMBER,
                &EntryNumber, &ReturnLength);
  init_itemlist(&NukeItemList[0], 0, SJC$_HOLD, NULL, NULL);
  
  /* make the call */
  Status = sys$sndjbcw(0, SJC$_ALTER_JOB, 0, NukeItemList, &KillIOSB,
                       NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

SV *
release_entry(EntryNumber)
     int EntryNumber
   CODE:
{
  ITMLST NukeItemList[3];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 3);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], sizeof(EntryNumber), SJC$_ENTRY_NUMBER,
                &EntryNumber, &ReturnLength);
  init_itemlist(&NukeItemList[0], 0, SJC$_NO_HOLD, NULL, NULL);
  
  /* make the call */
  Status = sys$sndjbcw(0, SJC$_ALTER_JOB, 0, NukeItemList, &KillIOSB,
                       NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

  
SV *
delete_form(FormName)
     char *FormName
   CODE:
{
  ITMLST NukeItemList[2];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 2);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], strlen(FormName), SJC$_FORM_NAME,
                FormName, &ReturnLength);

  /* make the call */
  Status = sys$sndjbcw(0, SJC$_DELETE_FORM, 0, NukeItemList, &KillIOSB,
                       NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

  
SV *
delete_characteristic(CharacteristicName)
     char *CharacteristicName
   CODE:
{
  ITMLST NukeItemList[2];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 2);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], strlen(CharacteristicName),
                SJC$_CHARACTERISTIC_NAME, CharacteristicName,
                &ReturnLength);

  /* make the call */
  Status = sys$sndjbcw(0, SJC$_DELETE_CHARACTERISTIC, 0, NukeItemList,
                       &KillIOSB, NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

  
SV *
delete_queue(QueueName)
     char *QueueName
   CODE:
{
  ITMLST NukeItemList[2];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 2);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], strlen(QueueName), SJC$_QUEUE,
                QueueName, &ReturnLength);

  /* make the call */
  Status = sys$sndjbcw(0, SJC$_DELETE_QUEUE, 0, NukeItemList, &KillIOSB,
                       NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

SV *
stop_queue(QueueName)
     char *QueueName
   CODE:
{
  ITMLST NukeItemList[2];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 2);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], strlen(QueueName), SJC$_QUEUE,
                QueueName, &ReturnLength);

  /* make the call */
  Status = sys$sndjbcw(0, SJC$_STOP_QUEUE, 0, NukeItemList, &KillIOSB,
                       NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

SV *
pause_queue(QueueName)
     char *QueueName
   CODE:
{
  ITMLST NukeItemList[2];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 2);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], strlen(QueueName), SJC$_QUEUE,
                QueueName, &ReturnLength);

  /* make the call */
  Status = sys$sndjbcw(0, SJC$_PAUSE_QUEUE, 0, NukeItemList, &KillIOSB,
                       NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

SV *
start_queue(QueueName)
     char *QueueName
   CODE:
{
  ITMLST NukeItemList[2];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 2);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], strlen(QueueName), SJC$_QUEUE,
                QueueName, &ReturnLength);

  /* make the call */
  Status = sys$sndjbcw(0, SJC$_START_QUEUE, 0, NukeItemList, &KillIOSB,
                       NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

SV *
reset_queue(QueueName)
     char *QueueName
   CODE:
{
  ITMLST NukeItemList[2];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 2);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], strlen(QueueName), SJC$_QUEUE,
                QueueName, &ReturnLength);

  /* make the call */
  Status = sys$sndjbcw(0, SJC$_RESET_QUEUE, 0, NukeItemList, &KillIOSB,
                       NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}
  
SV *
delete_manager(ManagerName)
     char *ManagerName
   CODE:
{
  ITMLST NukeItemList[2];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 2);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], strlen(ManagerName),
                SJC$_QUEUE_MANAGER_NAME, ManagerName, &ReturnLength);

  /* make the call */
  Status = sys$sndjbcw(0, SJC$_DELETE_QUEUE_MANAGER, 0, NukeItemList,
                       &KillIOSB, NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

SV *
start_manager(ManagerName)
     char *ManagerName
   CODE:
{
  ITMLST NukeItemList[2];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 2);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], strlen(ManagerName),
                SJC$_QUEUE_MANAGER_NAME, ManagerName, &ReturnLength);

  /* make the call */
  Status = sys$sndjbcw(0, SJC$_START_QUEUE_MANAGER, 0, NukeItemList,
                       &KillIOSB, NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

SV *
stop_manager(ManagerName)
     char *ManagerName
   CODE:
{
  ITMLST NukeItemList[2];
  int Status;
  short ReturnLength;
  iosb KillIOSB;
  
  /* Clear the item list */
  memset(NukeItemList, 0, sizeof(ITMLST) * 2);

  /* Fill the list in */
  init_itemlist(&NukeItemList[0], strlen(ManagerName),
                SJC$_QUEUE_MANAGER_NAME, ManagerName, &ReturnLength);

  /* make the call */
  Status = sys$sndjbcw(0, SJC$_STOP_QUEUE_MANAGER, 0, NukeItemList,
                       &KillIOSB, NULL, NULL);

  /* If there's an abnormal return, then note it */
  if (Status != SS$_NORMAL) {
    SETERRNO(EVMSERR, Status);
    ST(0) = &sv_undef;
  } else {
    /* We returned SS$_NORMAL. Was there another problem? */
    if (KillIOSB.sts != JBC$_NORMAL) {
      croak(decode_jbc(KillIOSB.sts));
    } else {
      /* Guess everything's OK. Exit normally */
      ST(0) = &sv_yes;
    }
  }
}

  
