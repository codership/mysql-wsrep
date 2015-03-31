/* Copyright 2015 Codership Oy <http://www.codership.com>

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; version 2 of the License.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

//! @file some utility functions and classes not directly related to replication

#include "wsrep_xid.h"
#include "sql_class.h"
#include "wsrep_mysqld.h" // for logging macros

static inline wsrep_seqno_t
wsrep_seqno_byteswap(wsrep_seqno_t const seqno)
{
  union { wsrep_seqno_t s; uint8_t b[8]; } from, to;

  from.s = seqno;

  to.b[0] = from.b[7]; to.b[1] = from.b[6];
  to.b[2] = from.b[5]; to.b[3] = from.b[4];
  to.b[4] = from.b[3]; to.b[5] = from.b[2];
  to.b[6] = from.b[1]; to.b[7] = from.b[0];

  return to.s;
}

/* Since vast majority of existing installations are little-endian and
 * for the general little-endian cause, canonical XID seqno representation
 * is little-endian. */
#ifdef WORDS_BIGENDIAN
  #define HOST_TO_XID_SEQNO(s) wsrep_seqno_byteswap(s)
#else
  #define HOST_TO_XID_SEQNO(s) (s)
#endif
#define XID_TO_HOST_SEQNO(s) HOST_TO_XID_SEQNO(s)

/*
 * WSREPXid
 */

#define WSREP_XID_PREFIX_1 "WSREPXid" // seqno in host order
#define WSREP_XID_PREFIX_2 "WS_XID_2" // seqno in little-endian order
#define WSREP_XID_PREFIX WSREP_XID_PREFIX_2 // current version
#define WSREP_XID_PREFIX_LEN MYSQL_XID_PREFIX_LEN
#define WSREP_XID_UUID_OFFSET 8
#define WSREP_XID_SEQNO_OFFSET (WSREP_XID_UUID_OFFSET + sizeof(wsrep_uuid_t))
#define WSREP_XID_GTRID_LEN (WSREP_XID_SEQNO_OFFSET + sizeof(wsrep_seqno_t))

void wsrep_xid_init(XID& xid, const wsrep_uuid_t& uuid, wsrep_seqno_t seqno)
{
  seqno= HOST_TO_XID_SEQNO(seqno);
  xid.formatID= 1;
  xid.gtrid_length= WSREP_XID_GTRID_LEN;
  xid.bqual_length= 0;
  memset(xid.data, 0, sizeof(xid.data));
  memcpy(xid.data, WSREP_XID_PREFIX, WSREP_XID_PREFIX_LEN);
  memcpy(xid.data + WSREP_XID_UUID_OFFSET,  &uuid,  sizeof(wsrep_uuid_t));
  memcpy(xid.data + WSREP_XID_SEQNO_OFFSET, &seqno, sizeof(wsrep_seqno_t));
}

// returns XID version, 0 if not a wsrep XID
int wsrep_is_wsrep_xid(const void* xid_ptr)
{
  const XID* xid= reinterpret_cast<const XID*>(xid_ptr);

  if (xid->formatID     == 1                   &&
      xid->gtrid_length == WSREP_XID_GTRID_LEN &&
      xid->bqual_length == 0)
  {
    if (!memcmp(xid->data, WSREP_XID_PREFIX_2, WSREP_XID_PREFIX_LEN))
      return 2;
    if (!memcmp(xid->data, WSREP_XID_PREFIX_1, WSREP_XID_PREFIX_LEN))
      return 1;
  }

  return 0;
}

const wsrep_uuid_t* wsrep_xid_uuid(const XID& xid)
{
  if (wsrep_is_wsrep_xid(&xid))
    return reinterpret_cast<const wsrep_uuid_t*>(xid.data
                                                 + WSREP_XID_UUID_OFFSET);
  else
    return &WSREP_UUID_UNDEFINED;
}

wsrep_seqno_t wsrep_xid_seqno(const XID& xid)
{
  int const xid_ver = wsrep_is_wsrep_xid(&xid);
  if (xid_ver)
  {
    wsrep_seqno_t seqno;
    memcpy(&seqno, xid.data + WSREP_XID_SEQNO_OFFSET, sizeof(wsrep_seqno_t));
#ifdef WORDS_BIGENDIAN
    if (xid_ver >= 2)
      return XID_TO_HOST_SEQNO(seqno);
    else
#endif /* WORDS_BIGENDIAN */
    return seqno; // host and XID orders are the same
  }
  else
  {
    return WSREP_SEQNO_UNDEFINED;
  }
}

static my_bool set_SE_checkpoint(THD* unused, plugin_ref plugin, void* arg)
{
  XID* xid= static_cast<XID*>(arg);
  handlerton* hton= plugin_data(plugin, handlerton *);

  if (hton->db_type == DB_TYPE_INNODB)
  {
    const wsrep_uuid_t* uuid(wsrep_xid_uuid(*xid));
    char uuid_str[40] = {0, };
    wsrep_uuid_print(uuid, uuid_str, sizeof(uuid_str));
    WSREP_DEBUG("Set WSREPXid for InnoDB:  %s:%lld",
                uuid_str, (long long)wsrep_xid_seqno(*xid));
    hton->wsrep_set_checkpoint(hton, xid);
  }

  return FALSE;
}

void wsrep_set_SE_checkpoint(XID& xid)
{
  plugin_foreach(NULL, set_SE_checkpoint, MYSQL_STORAGE_ENGINE_PLUGIN, &xid);
}

void wsrep_set_SE_checkpoint(const wsrep_uuid_t& uuid, wsrep_seqno_t seqno)
{
  XID xid;
  wsrep_xid_init(xid, uuid, seqno);
  wsrep_set_SE_checkpoint(xid);
}

static my_bool get_SE_checkpoint(THD* unused, plugin_ref plugin, void* arg)
{
  XID* xid= static_cast<XID*>(arg);
  handlerton* hton= plugin_data(plugin, handlerton *);

  if (hton->db_type == DB_TYPE_INNODB)
  {
    hton->wsrep_get_checkpoint(hton, xid);
    const wsrep_uuid_t* uuid(wsrep_xid_uuid(*xid));
    char uuid_str[40] = {0, };
    wsrep_uuid_print(uuid, uuid_str, sizeof(uuid_str));
    WSREP_DEBUG("Read WSREPXid from InnoDB:  %s:%lld",
                uuid_str, (long long)wsrep_xid_seqno(*xid));
  }

  return FALSE;
}

void wsrep_get_SE_checkpoint(XID& xid)
{
  plugin_foreach(NULL, get_SE_checkpoint, MYSQL_STORAGE_ENGINE_PLUGIN, &xid);
}

void wsrep_get_SE_checkpoint(wsrep_uuid_t& uuid, wsrep_seqno_t& seqno)
{
  uuid= WSREP_UUID_UNDEFINED;
  seqno= WSREP_SEQNO_UNDEFINED;

  XID xid;
  memset(&xid, 0, sizeof(xid));
  xid.formatID= -1;

  wsrep_get_SE_checkpoint(xid);

  if (xid.formatID == -1) return; // nil XID

  if (!wsrep_is_wsrep_xid(&xid))
  {
    WSREP_WARN("Read non-wsrep XID from storage engines.");
    return;
  }

  uuid= *wsrep_xid_uuid(xid);
  seqno= wsrep_xid_seqno(xid);
}
