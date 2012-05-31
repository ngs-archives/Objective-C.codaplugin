#!/usr/bin/perl -w

use strict;
use warnings;
use Data::Dumper;

my $code = $ENV{CODA_SELECTED_TEXT};
my @synthesize;
my @encode_with_coder;
my @init_with_coder;
my @copy_with_zone;

my $class_name;

while($code =~ /([^\n]+)\n?/g) {
  my $line = $1;
  
  if(!$class_name && $line =~ /\@interface\s+([^:\s]+).+/) {
    $class_name = $1;
    next;
  }
  
  my ( $attr, $type, $varname ) = $line =~ m/\@property\s*\(([\w,]+)\)\s*([^\s]+)\s*\*?([^;]+);/;
  next if !$varname || $attr =~ /readonly/;
  my $encode_method = undef;
  
  if($attr =~ /copy/) {
    $encode_method = 'Object';
    push @copy_with_zone, "  newCopy.${varname} = self.${varname};";
  } elsif($attr =~ /(retain|strong)/ ) {
    $encode_method = 'Object';
    push @copy_with_zone, "  newCopy.${varname} = [self.${varname} copyWithZone:zone];";
  } else {
    push @copy_with_zone, "  newCopy.${varname} = self.${varname};";
    if($type eq 'BOOL') {
      $encode_method = 'Bool';
    } elsif($type eq 'NSInteger') {
      $encode_method = 'Integer';
    } elsif($type eq 'int') {
      $encode_method = 'Int';
    } elsif($type eq 'int32_t') {
      $encode_method = 'Int32';
    } elsif($type eq 'int64_t') {
      $encode_method = 'Int64';
    } elsif($type eq 'float' || $type eq 'CGFloat') {
      $encode_method = 'Float';
    } elsif($type eq 'double') {
      $encode_method = 'Double';
    }
  }
  
  push @synthesize, "\@synthesize $varname = _$varname;";
  if($encode_method) {
    push @encode_with_coder, "  [aCoder encode${encode_method}:self.${varname} forKey:@\"${varname}\"];";
    push @init_with_coder, "    self.${varname} = [aDecoder decode${encode_method}ForKey:@\"${varname}\"];";
  }
}

my $synthesize        = join("\n", @synthesize);
my $encode_with_coder = join("\n", @encode_with_coder);
my $init_with_coder   = join("\n", @init_with_coder);
my $copy_with_zone    = join("\n", @copy_with_zone);

my $output =<<EOM;

\@implementation $class_name

#pragma mark - Synthesize Accessors

$synthesize

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder {
  if(self=[self init]) {
$init_with_coder
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
$encode_with_coder
}

#pragma mark - NSCopying


- (id)copyWithZone:(NSZone *)zone {
  $class_name* newCopy = [[[self class] alloc] init];
$copy_with_zone
  return newCopy;
}

\@end

EOM

print $output;