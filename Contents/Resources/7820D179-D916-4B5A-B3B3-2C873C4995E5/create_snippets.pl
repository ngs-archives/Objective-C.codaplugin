#!/usr/bin/perl -w

use strict;
use warnings;
use Data::Dumper;

my $code = $ENV{CODA_SELECTED_TEXT} || join '', <STDIN>;
my @synthesize;
my @encode_with_coder;
my @init_with_coder;
my @copy_with_zone;
my @init_with_dictionary;
my @includes;
my @header;
my @dictionary;

sub decamelize {
	my $s = shift;
	$s =~ s{([^a-zA-Z]?)([A-Z]*)([A-Z])([a-z]?)}{
		my $fc = pos($s)==0;
		my ($p0,$p1,$p2,$p3) = ($1,lc$2,lc$3,$4);
		my $t = $p0 || $fc ? $p0 : '_';
		$t .= $p3 ? $p1 ? "${p1}_$p2$p3" : "$p2$p3" : "$p1$p2";
		$t;
	}ge;
	$s;
}

#"

my $class_name;

while($code =~ /([^\n]+)\n?/g) {
  my $line = $1;
  
  if(!$class_name && $line =~ /^\/\//) {
    push @header, $line;
  }
  if(!$class_name && $line =~ /\@interface\s+([^:\s]+).+/) {
    $class_name = $1;
    push @includes, "#include \"${class_name}.h\"";
    next;
  }
  my ( $attr, $type, $varname ) = $line =~ m/\@property\s*\(([\w,]+)\)\s*([^\s]+)\s*\*?([^;]+);/;
  next if !$varname || $attr =~ /readonly/;
  my $encode_method = undef;
  
  push @init_with_dictionary, "    if([dictionary objectForKey:@\"${varname}\"])";
  
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
  my $is_object = $encode_method eq 'Object';
  my $is_foundation = $is_object && $type =~ /^NS/;
  my $key = decamelize($varname);
  
  ( my $valmethod = lc $encode_method ) =~ s/\d+//g;
  
  my ($in_var, $out_var);
  if($is_foundation) {
    $in_var = "[dictionary valueForKey:@\"${key}\"]";
    $out_var = "self.${varname}";
  } elsif($is_object) {
    $in_var = "[[${type} alloc] initWithDictionary:[dictionary objectForKey:@\"${key}\"]]";
    $out_var = "[self.${varname} dictionary]";
  } else {
    $in_var = "[[dictionary valueForKey:@\"${key}\"] ${valmethod}Value];";
    $out_var = "[NSNumber numberWith${encode_method}:self.${varname}]";
  }
  push @init_with_dictionary, "      self.${varname} = $in_var;";
  push @dictionary, "          ${out_var}, @\"${key}\",";
  push @synthesize, "\@synthesize $varname = _$varname;";
  push @includes, "#include \"${type}.h\""  if(!$is_foundation && $is_object );
  if($encode_method) {
    push @encode_with_coder, "  [aCoder encode${encode_method}:self.${varname} forKey:@\"${key}\"];";
    push @init_with_coder, "    self.${varname} = [aDecoder decode${encode_method}ForKey:@\"${key}\"];";
  }
}

my $synthesize           = join("\n", @synthesize);
my $encode_with_coder    = join("\n", @encode_with_coder);
my $init_with_coder      = join("\n", @init_with_coder);
my $copy_with_zone       = join("\n", @copy_with_zone);
my $init_with_dictionary = join("\n", @init_with_dictionary);

my $includes   = join("\n", @includes);
my $dictionary = join("\n", @dictionary);

( my $header = join("\n", @header) ) =~ s/\/\/(\s*)$class_name\.h/\/\/$1$class_name.m/;

my $output =<<EOM;
$header

$includes

\@implementation $class_name

#pragma mark - Synthesize Accessors

$synthesize

#pragma mark - Dictionary

- (id)initWithDictionary:(NSDictionary *)dictionary {
  if(self=[super initWithDictionary:dictionary]) {
$init_with_dictionary
  }
  return self;
}

- (NSDictionary *)dictionary {
  return [NSDictionary dictionaryWithObjectsAndKeys:
$dictionary
          nil];
}


#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder {
  if(self=[super initWithCoder:aDecoder]) {
$init_with_coder
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
  [super encodeWithCoder:aCoder]; 
$encode_with_coder
}

#pragma mark - NSCopying


- (id)copyWithZone:(NSZone *)zone {
  $class_name* newCopy = [super copyWithZone:zone];
$copy_with_zone
  return newCopy;
}

\@end

EOM

print $output;