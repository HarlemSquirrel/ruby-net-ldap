# $Id$
#
# Copyright (C) 2006 by Francis Cianfrocca. All Rights Reserved.
# Gmail account: garbagecat10.
#
# This is an LDAP server intended for unit testing of Net::LDAP.
# It implements as much of the protocol as we have the stomach
# to implement but serves static data. Use ldapsearch to test
# this server!
#
# To make this easier to write, we use the Ruby/EventMachine
# reactor library.
#


require 'stringio'

#------------------------------------------------

class String
  def read_ber! syntax=nil
    s = StringIO.new self
    pdu = s.read_ber(syntax)
    if pdu
      if s.eof?
        slice!(0, length)
      else
        slice!(0, length - s.read.length)
      end
    end
    pdu
  end
end


module LdapServer

  LdapServerAsnSyntax = {
    :application => {
      :constructed => {
        0 => :array,               # LDAP BindRequest
        3 => :array                # LDAP SearchRequest
      },
      :primitive => {
        2 => :string               # ldapsearch sends this to unbind
      }
    },
    :context_specific => {
      :primitive => {
        0 => :string               # simple auth (password)
      },
    }
  }

  def post_init
    $logger.info "Accepted LDAP connection"
    @authenticated = false
  end

  def receive_data data
    @data ||= ""; @data << data
    while pdu = @data.read_ber!(LdapServerAsnSyntax)
      begin
      handle_ldap_pdu pdu
      rescue
        $logger.error "closing connection due to error #{$!}"
        close_connection
      end
    end
  end

  def handle_ldap_pdu pdu
    tag_id = pdu[1].ber_identifier
    case tag_id
    when 0x60
      handle_bind_request pdu
    when 0x63
      handle_search_request pdu
    when 0x42
      # bizarre thing, it's a null object (primitive application-2)
      # sent by ldapsearch to request an unbind (or a kiss-off, not sure which)
      close_connection_after_writing
    else
      $logger.error "received unknown packet-type #{tag_id}"
      close_connection_after_writing
    end
  end

  def handle_bind_request pdu
    # TODO, return a proper LDAP error instead of blowing up on version error
    if pdu[1][0] != 3
      send_ldap_response 1, pdu[0].to_i, 2, "", "We only support version 3"
    elsif pdu[1][1] != "cn=bigshot,dc=bayshorenetworks,dc=com"
      send_ldap_response 1, pdu[0].to_i, 48, "", "Who are you?"
    elsif pdu[1][2].ber_identifier != 0x80
      send_ldap_response 1, pdu[0].to_i, 7, "", "Keep it simple, man"
    elsif pdu[1][2] != "opensesame"
      send_ldap_response 1, pdu[0].to_i, 49, "", "Make my day"
    else
      @authenticated = true
      send_ldap_response 1, pdu[0].to_i, 0, pdu[1][1], "I'll take it"
    end
  end

  def handle_search_request pdu
    unless @authenticated
      send_ldap_response 5, pdu[0].to_i, 50, "", "Who did you say you were?"
      return
    end

    treebase = pdu[1][0]
    if treebase != "dc=bigdomain,dc=com"
      send_ldap_response 5, pdu[0].to_i, 32, "", "unknown treebase"
      return
    end

=begin
Search Response ::=
      CHOICE {
           entry          [APPLICATION 4] SEQUENCE {
                               objectName     LDAPDN,
                               attributes     SEQUENCE OF SEQUENCE {
                                                   AttributeType,
                                                   SET OF AttributeValue
                                              }
                          },
           resultCode     [APPLICATION 5] LDAPResult
       }
=end

    send_data( [
      pdu[0].to_i.to_ber, [
        "abcdefghijklmnopqrstuvwxyz".to_ber, [

          [
            "mail".to_ber, ["aaa".to_ber, "bbb".to_ber, "ccc".to_ber].to_ber_set
          ].to_ber_sequence,
          [
            "objectclass".to_ber, ["111".to_ber, "222".to_ber, "333".to_ber].to_ber_set
          ].to_ber_sequence,
          [
            "cn".to_ber, ["CNCNCNCN".to_ber].to_ber_set
          ].to_ber_sequence,

        ].to_ber_sequence
      ].to_ber_appsequence(4)
    ].to_ber_sequence)

    send_data( [
      pdu[0].to_i.to_ber, [
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ".to_ber, [

          [
            "mail".to_ber, ["aaa".to_ber, "bbb".to_ber, "ccc".to_ber].to_ber_set
          ].to_ber_sequence,
          [
            "objectclass".to_ber, ["111".to_ber, "222".to_ber, "333".to_ber].to_ber_set
          ].to_ber_sequence,
          [
            "cn".to_ber, ["CNCNCNCN".to_ber].to_ber_set
          ].to_ber_sequence,

        ].to_ber_sequence
      ].to_ber_appsequence(4)
    ].to_ber_sequence)

    send_ldap_response 5, pdu[0].to_i, 0, "", "Was that what you wanted?"
  end

  def send_ldap_response pkt_tag, msgid, code, dn, text
    send_data( [msgid.to_ber, [code.to_ber, dn.to_ber, text.to_ber].to_ber_appsequence(pkt_tag) ].to_ber )
  end

end


#------------------------------------------------

if __FILE__ == $0

  require 'rubygems'
  require 'eventmachine'

  require 'logger'
  $logger = Logger.new $stderr

  $logger.info "adding ../lib to loadpath, to pick up dev version of Net::LDAP."
  $:.unshift "../lib"

  require 'netber'
  require 'ldappdu'
  require 'netldap'
  require 'netldapfilter'

  EventMachine.run {
    $logger.info "starting LDAP server on 127.0.0.1 port 3890"
    EventMachine.start_server "127.0.0.1", 3890, LdapServer
    EventMachine.add_periodic_timer 60, proc {$logger.info "heartbeat"}
  }
end

