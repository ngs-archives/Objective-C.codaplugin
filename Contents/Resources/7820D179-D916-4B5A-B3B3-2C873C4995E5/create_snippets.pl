#!/usr/bin/perl -w

use strict;
use warnings;
use Data::Dumper;

my $code = $ENV{CODA_SELECTED_TEXT} || join '', <STDIN>;
my @encode_with_coder;
my @init_with_coder;
my @copy_with_zone;
my @init_with_dictionary;
my @includes;
my @header;
my @dictionary;
my $copying = 1;

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
  if(!$class_name && $line =~ /\@interface\s+([^:\s]+)(.+)/) {
    $class_name = $1;
    $copying = $2 !~ /NSCopying/;
    push @includes, "#import \"${class_name}.h\"";
    next;
  }
  my ( $attr, $type, $varname ) = $line =~ m/\@property\s*\(([\w,\s]+)\)\s*([^\s]+)\s*\*?([^;]+);/;
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
  my $is_object = $encode_method eq 'Object';
  my $is_foundation = $is_object && $type =~ /^NS/;
  my $is_nsurl = $type eq 'NSURL';
  my $key = decamelize($varname);
  
  my $if = "[dictionary[@\"${key}\"] isKindOfClass:[NSString class]]";
  $if = "($if ||\n[dictionary[@\"${key}\"] isKindOfClass:[NSNumber class]])" unless $is_object;
  push @init_with_dictionary, "    if(dictionary[@\"${key}\"]&&\n${if})";
  
  ( my $valmethod = lc $encode_method ) =~ s/\d+//g;
  
  my ($in_var, $out_var);
  if($is_nsurl) {
    $in_var = "[NSURL URLWithString:dictionary[@\"${key}\"]]";
    $out_var = "self.${varname}.absoluteString";
  } elsif($is_foundation) {
    $in_var = "dictionary[@\"${key}\"]";
    $out_var = "self.${varname}";
  } elsif($is_object) {
    $in_var = "[[${type} alloc] initWithDictionary:dictionary[\@\"${key}\"]]";
    $out_var = "[self.${varname} dictionary]";
  } else {
    $in_var = "[dictionary[\@\"${key}\"] ${valmethod}Value]";
    $out_var = "\@\(self.${varname}\)";
  }
  push @init_with_dictionary, "      self.${varname} = $in_var;";
  push @dictionary, "          \@\"${key}\" : ${out_var}";
  push @includes, "#import \"${type}.h\""  if(!$is_foundation && $is_object );
  if($encode_method) {
    push @encode_with_coder, "  [aCoder encode${encode_method}:self.${varname} forKey:\@\"${key}\"];";
    push @init_with_coder, "    self.${varname} = [aDecoder decode${encode_method}ForKey:\@\"${key}\"];";
  }
}

my $encode_with_coder    = join("\n", @encode_with_coder);
my $init_with_coder      = join("\n", @init_with_coder);
my $copy_with_zone       = join("\n", @copy_with_zone);
my $init_with_dictionary = join("\n", @init_with_dictionary);

my $includes   = join("\n", @includes);
my $dictionary = join(",\n", @dictionary);

( my $header = join("\n", @header) ) =~ s/\/\/(\s*)$class_name\.h/\/\/$1$class_name.m/;

my $super_init_with_dictionary = $copying ? '[super initWithDictionary:dictionary]' : '[super init]';
my $super_init_with_coder = $copying ? '[super initWithCoder:aDecoder]' : '[super init]';
my $super_encode_with_coder = $copying ? '  [super encodeWithCoder:aCoder];' : '';
my $super_copy_with_zone = $copying ? '[super copyWithZone:zone]' : '[[[self class] alloc] init]';


my $output =<<EOM;
$header

$includes

\@implementation $class_name

#pragma mark - Dictionary

- (id)initWithDictionary:(NSDictionary *)dictionary {
  if(self=$super_init_with_dictionary) {
$init_with_dictionary
  }
  return self;
}

- (NSDictionary *)dictionary {
  return \@{
$dictionary
  };
}


#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)aDecoder {
  if(self=$super_init_with_coder) {
$init_with_coder
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder {
$super_encode_with_coder
$encode_with_coder
}

#pragma mark - NSCopying


- (id)copyWithZone:(NSZone *)zone {
  $class_name* newCopy = $super_copy_with_zone;
$copy_with_zone
  return newCopy;
}

\@end

EOM

print $output;