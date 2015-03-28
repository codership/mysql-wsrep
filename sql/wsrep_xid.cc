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
  #define host_to_xid_seqno(s) wsrep_seqno_byteswap(s)
  static inline wsrep_seqno_t
  xid_to_host_seqno(wsrep_seqno_t const seqno)
  {
    // a little trick to simplify migration for existing installations:
    // it is highly inlikely that the current seqno in any big-endian
    // production cluster exceeds 0x0000000fffffffffLL (64G).
    // Hence any seqno read from XID that is bigger than that must have been
    // written in BE format. This BE detection has failure probability of
    // 1 in 256M. This must be removed after next release.
    wsrep_seqno_t const ret(wsrep_seqno_byteswap(seqno));
    return (ret > 0x0000000fffffffffLL || ret < WSREP_SEQNO_UNDEFINED ?
            seqno : ret);
  }
#else
  #define host_to_xid_seqno(s) (s)
  #define xid_to_host_seqno(s) host_to_xid_seqno(s)
#endif

/*
 * WSREPXid
 */

#define WSREP_XID_PREFIX "WSREPXid"
#define WSREP_XID_PREFIX_LEN MYSQL_XID_PREFIX_LEN
#define WSREP_XID_UUID_OFFSET 8
#define WSREP_XID_SEQNO_OFFSET (WSREP_XID_UUID_OFFSET + sizeof(wsrep_uuid_t))
#define WSREP_XID_GTRID_LEN (WSREP_XID_SEQNO_OFFSET + sizeof(wsrep_seqno_t))

void wsrep_xid_init(XID& xid, const wsrep_uuid_t& uuid, wsrep_seqno_t seqno)
{
  seqno= host_to_xid_seqno(seqno);
  xid.formatID= 1;
  xid.gtrid_length= WSREP_XID_GTRID_LEN;
  xid.bqual_length= 0;
  memset(xid.data, 0, sizeof(xid.data));
  memcpy(xid.data, WSREP_XID_PREFIX, WSREP_XID_PREFIX_LEN);
  memcpy(xid.data + WSREP_XID_UUID_OFFSET,  &uuid,  sizeof(wsrep_uuid_t));
  memcpy(xid.data + WSREP_XID_SEQNO_OFFSET, &seqno, sizeof(wsrep_seqno_t));
}

int wsrep_is_wsrep_xid(const void* xid_ptr)
{
  const XID* xid= reinterpret_cast<const XID*>(xid_ptr);
  return (xid->formatID      == 1                   &&
          xid->gtrid_length  == WSREP_XID_GTRID_LEN &&
          xid->bqual_length  == 0                   &&
          !memcmp(xid->data, WSREP_XID_PREFIX, WSREP_XID_PREFIX_LEN));
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
  if (wsrep_is_wsrep_xid(&xid))
  {
    wsrep_seqno_t seqno;
    memcpy(&seqno, xid.data + WSREP_XID_SEQNO_OFFSET, sizeof(wsrep_seqno_t));
    return xid_to_host_seqno(seqno);
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
