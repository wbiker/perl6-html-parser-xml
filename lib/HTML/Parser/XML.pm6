#!/usr/bin/env perl6
use XML;

class HTML::Parser::XML {
  has %!formtags = qw<input 1 option 1 optgroup 1 select 1 button 1 datalist 1 textarea 1>;
  has %!openisclose = {
    tr => %(qw<tr 1 th 1 td 1 >),
    th => %(qw<th 1>),
    td => %(qw<thead 1 td 1>),
    body => %(qw<head 1 link 1 script 1>),
    li => %(qw<li 1>),
    p => %(qw<p 1>),
    input => %!formtags,
    option => %!formtags,
    optgroup => %!formtags,
    select => %!formtags,
    button => %!formtags,
    datalist => %!formtags,
    textarea => %!formtags,
    option => %(qw<option 1>),
    optgroup => %(qw<optgroup 1>),
  };
  has %!specials = qw<script 1 style 1>;
  has Str           $.html   is rw;
  has Int           $.index  is rw;
  has XML::Document $.xmldoc is rw;
  has Int           %.flags = enum <INSCRIPT INSTYLE>;
  has %!voids = qw«__proto__ 1 area 1 base 1 basefront 1 br 1 col 1 command 1 embed 1 frame 1 hr 1 img 1 input 1 isindex 1 keygen 1 link 1 meta 1 param 1 source 1 track 1 wbr 1 path 1 circle 1 ellipse 1 line 1 rect 1 use 1»;
  method !ds {
    while $.html.substr($.index, 1) ~~ m{\s} { 
      $.index++; 
    }
  }


  method parse (Str $html) {
    my enum state «NIL INATTRKEY INATTRVAL»;
    $.index     = 0;
    $.html      = $html;
    my $buffer  = '';
    my $status  = NIL;
    my $cparent = XML::Element.new: name => 'nil';
    my $cbuffer = '';
    my $tbuffer = '';
    my $mquote  = '';
    my $bindex  = 0;
    my $qnest   = 0;
    my %attrbuf = Hash.new;
    my @nest    = Array.new;
    my $aclose  = 0;
    $.xmldoc = XML::Document.new: root => $cparent; 
    @nest.push: $.xmldoc.root;
    while $.index < $.html.chars {
      $cbuffer = $.html.substr($.index, 1);
      if $cbuffer eq '<' {
        #build tag and attributes
        if $.html.substr($.index + 1, 1) !~~ m/\s/ {
          $cbuffer = $.html.substr(++$.index, 1);
          $buffer  = '';
          my ($tag, $id, %attr);
          $tag = '';
          $id  = '';
          $aclose = 0;
          %attr = Hash.new;
          #gather the tag
          while $cbuffer !~~ m« [ \s | '>' ] » {
            $tag    ~= $cbuffer;
            $cbuffer = $.html.substr(++$.index, 1);
          }
          $tag = lc $tag;
          #gather the attributes
          self!ds if $cbuffer !~~ m{ [ '>' | '/' ] };
          $cbuffer = $.html.substr($.index, 1);
          $qnest = 0;
          if $tag eq '!--' {
            while $.html.substr($.index, 3) ne '-->' {
              $buffer ~= $.html.substr($.index,1);
              $.index++;
            }
            $.index += 3;
          } else {
            while $cbuffer !~~ m{ [ '>' | '/' ] } || $qnest == 1 {
              $buffer ~= $cbuffer;
              $cbuffer = $.html.substr(++$.index, 1);
              $mquote  = $cbuffer if $cbuffer ~~ m{ [ '"' | '\'' ] } && $qnest == 0;
              $qnest   = 1, next  if $cbuffer ~~ m{ [ '"' | '\'' ] } && $qnest == 0;
              $qnest   = 0        if $cbuffer eq $mquote && $qnest == 1;
            }
            $.index++;
            { $aclose = 1; ++$.index; $cbuffer = $.html.substr($.index, 1); } if $cbuffer eq '/';
          }
          #parse attribute string;
          $bindex  = 0;
          %attrbuf = key => '', value => '';
          %attr<text> = $buffer if $tag eq '!--';
          if $tag ne '!--' {
            while $bindex < $buffer.chars {
              $cbuffer = $buffer.substr($bindex++, 1);
              if ( $cbuffer ~~ m{ \s } && ( ( $status eq INATTRVAL && $mquote eq '' ) || $status eq INATTRKEY ) ) || ( $cbuffer eq $mquote && $status eq INATTRVAL ) {
                if $status ne NIL {
                  %attr{%attrbuf<key>} = %attrbuf eq '' ?? Nil !! %attrbuf<value>;
                }
                %attrbuf = key => '', value => '';
                $status = NIL;
                next;
              }
              #start building a key
              if $cbuffer !~~ m { [ '=' | \s ] } && ( $status eq NIL || $status eq INATTRKEY ) {
                %attrbuf<key> ~= $cbuffer;
                $status = INATTRKEY;
              }
              if $status eq INATTRVAL {
                %attrbuf<value> ~= $cbuffer;
              }
              if $cbuffer ~~ m { '=' } && $status eq INATTRKEY {
                $mquote = '';
                $mquote = $buffer.substr($bindex++, 1) if $buffer.substr($bindex, 1) ~~ m{ [ '"' | '\'' ] };
                $status = INATTRVAL;
              }
            }
            %attr{%attrbuf<key>} = %attrbuf<value> if %attrbuf<key> ne '';
          }
          
          #fast forward over specials
          if %!specials{$tag}.defined && %!specials{$tag} eq 1 {
            $.index++ while lc($.html.substr($.index, $tag.chars + 3)) ne "</$tag>";
          }
          #handle special cases
          $cbuffer = $.html.substr($.index, 1);

          if $tag.defined && $tag eq '!doctype' {
            try {
              %.xmldoc.root.attribs{%attr.keys} = %attr.values;
            };
          } elsif $tag.defined && $tag eq 'script' {
        
          } else {
            if $tag.substr(0,1) eq '/' {
              @nest[@nest.elems - 1].append(XML::Text.new(text => $tbuffer)) if $tag ne '!--' && $tbuffer ne '';
              $tbuffer = '';
              @nest.pop if @nest.elems > 2;
              %attr = ();
              $tag  = '';
            } else {
              try {
                my $node;
                $node = XML::Element.new(attribs => %attr, name => $tag) if $tag ne '!--';
                $node = XML::Comment.new(data => %attr<text>) if $tag eq '!--';
                @nest[@nest.elems - 1].append(XML::Text.new(text => $tbuffer)) if $tag ne '!--';
                @nest[@nest.elems - 1].append($node); 
                @nest.push($node) if $aclose == 0 && (!%!voids{$tag}.defined || %!voids{$tag} ne 1) && $node !~~ XML::Comment;
                $tbuffer = '';
              };
            }
            $status = NIL;
          }
        }
      } else {
        $tbuffer ~= $cbuffer;
        $.index++; 
      }
    }
  }

};
