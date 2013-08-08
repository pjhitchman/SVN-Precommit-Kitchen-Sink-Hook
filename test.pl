#! /usr/bin/env perl
# pre-commit-kitchen-sink-hook
########################################################################

use strict;
use warnings;
use feature qw(say);

use Data::Dumper;
use Getopt::Long;
use Pod::Usage;

use constant {
    SVNLOOK_DEFAULT	=> '/usr/bin/svnlook',
    SVN_REPO_DEFAULT	=> '/path/to/repository',
    SECTION_HEADER	=> qr/^\s*\[\s*(\w+)\s+(.*)\]\s*$/,
    PARAMETER_LINE	=> qr/^\s*(\w+)\s*=\s*(.*)$/,
};

use constant { 		#Control File Type (package Control)
    FILE_IN_REPO	=> "R",
    FILE_ON_SERVER	=> "F",
};

use constant {		#Revision file Type (package Configuration)
    TRANSACTION 	=> "T",
    REVISION		=> "R",
};


my %parameters = (
    file	=> '**/* */**',
);

my $file = Section->new( "ban", "This is a description", \%parameters );
say Dumper $file;

########################################################################
# PACKAGE Configuration
#
# Description
# Stores the configuration information for the transaction. This
# includes the initial parameters, the control files, the sections,
# the user, etc.
#    
package Configuration;
use Carp;

sub new {
    my $class		= shift;

    my $self = {};
    bless $self, $class;
    return $self;
}

sub Author {
    my $self		= shift;
    my $author		= shift;

    if ( defined $author ) {
	$self->Ldap_user($author);	#Preserved with spaces and case;
	$author =~ s/\s+/_/g;		#Replace whitespace with underscores
	$self->{AUTHOR} = lc $author;
    }
    return $self->{AUTHOR};
}

sub Ldap_user {
    my $self		= shift;
    my $ldap_user	= shift;

    if ( defined $ldap_user ) {
	$self->{LDAP_USER} = $ldap_user;
    }
    return $self->{LDAP_USER};
}

sub Repository {
    my $self		= shift;
    my $repository	= shift;

    if ( defined $repository ) {
	$repository =~ s{\\}{/}g;	#Change from Windows to Unix file separators
	$self->{REPOSITORY} = $repository;
    }

    return $self->{REPOSITORY};
}

sub Rev_param {
    my $self		= shift;
    my $rev_param	= shift;

    if ( defined $rev_param and  $rev_param =~ /^-[tr]/ )  {
	$self->{REV_PARAM} = $rev_param;
    }
    elsif ( defined $rev_param and $rev_param != /^[tr]/ ) {
	croak qq(Revision parameter must start with "-t" or "-r");
    }
    return $self->{REV_PARAM};
}

sub Svnlook {
    my $self		= shift;
    my $svnlook		= shift;

    if ( defined $svnlook ) {
	$self->{SVNLOOK} = $svnlook;
    }

    return $self->{SVNLOOK};
}

#
########################################################################

########################################################################
# PACKAGE Control_file
#
# Stores Location, Type, and Contents of the Control File
#
package Control_file;
use autodie;
use Carp;

use constant {
    FILE_IN_REPO	=> "R",
    FILE_ON_SERVER	=> "F",
};

sub new {
    my $class		= shift;
    my $type		= shift;
    my $file		= shift;
    my $configuration	= shift;	#Needed if file is in repository

    if ( not defined $type ) {
	croak qq/Must pass in control file type ("R" = in repository. "F" = File on Server")/;
    }
    if ( not defined $file ) {
	croak qq(Must pass in Control File's location);
    }

    if ( not $configuration->isa( "Configuration" ) ) {
	croak qq(Configuration parameter needs to be of a Class "Configuration");
    }
    if ( $type eq FILE_IN_REPO and not defined $configuration ) {
	croak qq(Need to pass a configuration when control file is in the repository);
    }

    my $self = {};
    bless $self, $class;
    $self->Location($type);
    $self->File($file);

    #
    # Get the contents of the file
    #

    if ( $type eq FILE_ON_SERVER ) {
	open my $control_file_fh, "<", $file;
	my @file_contents = < $control_file_fh >;
	close $control_file_fh;
	chomp @file_contents;
	$self->Contents(\@file_contents);
    }
    else {
	my $rev_param   = $configuration->Rev_param;
	my $svnlook     = $configuration->Svnlook;
	my $repository  = $configuration->Repository;
	my @file_contents;
	    eval {
		@file_contents = qx($svnlook cat $rev_param $repository $file);
	    };
	    if ($@) {
		croak qq(Couldn't retreive contents of control file "$file" from repository "$repository");
	    }
	    chomp @file_contents;
	    $self->Contents(\@file_contents);
    }
    return $self;
}

sub Location {
    my $self		= shift;
    my $location	= shift;

    if ( defined $location ) {
	$self->{LOCATION} = $location;
    }
    return $self->{LOCATION};
}

sub Type {
    my $self		= shift;
    my $type		= shift;

    if ( defined $type ) {
	if ( $type ne FILE_IN_REPO and $type ne FILE_ON_SERVER ) {
	    croak qq(Type must be either ") . FILE_IN_REPO
	    . qq(" or ") . FILE_ON_SERVER . qq(".);
	}
	$self->{TYPE} = $type;
    }
    return $self->{TYPE};
}

sub Contents {
    my $self		= shift;
    my @contents	= @{ shift() };

    if ( @contents ) {
	@contents = grep { not /^\s*[#;]/ } @contents;  #Remove comment lines
	@contents = grep { not /^\s*$/ } @contents;  #Remove blank lines
	my $self->{CONTENTS} = \@contents;
    }
    @contents = @{ $self->{CONTENTS} };
    return wantarray ? @contents : \@contents;
}
#
########################################################################

########################################################################
# PACKAGE Section
#
# Various Section Objects. Each one is a different type and has
# have different attributes. Master is for general definition
#

package Section;
use Data::Dumper;
use Carp;

sub new {
    my $class		= shift;
    my $type		= shift;
    my $description	= shift;
    my $parameter_ref	= shift;

    if ( not defined $type or not defined $description ) {
	croak qq(You must pass in the Section type and Description);
    }

    $type = ucfirst lc $type;	#In the form of a Sub-Class Name

    $class .= "::$type";

    my $self = {};
    bless $self, $class;

    if ( not $self->isa("Section") ) {
	croak qq(Invalid Section type "$type" in control file);
    }
    $self->Description($description);
    $self->Parameters($parameter_ref);
    return $self;
}

sub Description {
    my $self		= shift;
    my $description	= shift;

    if ( defined $description ) {
	$self->{DESCRIPTION} = $description;
    }
    return $self->{DESCRIPTION};
}


sub Parameters {
    my $self		= shift;
    my %parameters	= %{ shift() };
    my @req_methods	= @{ shift() };

    #
    # Call the various methods
    #
    my %methods;
    for my $parameter ( keys %parameters ) {
	my $method = ucfirst lc $parameter;
	if ( not $self->can( "$method" ) ) {
	    croak qq(Invalid parameter "$method" passed);
	}
	$self->$method( $parameters{$parameter} );
    }

    #
    # Make sure all required parameters are here
    #
    for my $method ( @req_methods ) {
	$method = ucfirst lc $method;
	if ( not $self->$method ) {
	    croak qq(Missing required parameter "$method");
	}
    }
    return 1;
}

sub glob2regex {
    my $glob = shift;

    # Due to collision when replacing "*" and "**", we use the NUL
    # character as a temporary replacement for "**" and then replace
    # "*". After this is done, we can replace NUL with ".*".

    $glob =~ s{\\}{/}g; 		#Change backslashes to forward slashes

    # Quote all regex characters
    ( my $regex = $glob ) =~ s{([\.\+\{\}\[\]])}{\\$1}g;

    # Replace double asterisks. Use \0 to mark place
    $regex =~ s{\*\*}{\0}g;

    # Replace single asterisks only
    $regex =~ s/\*/[^\/]*/g;

    # Replace ? with .
    $regex =~ s/\?/./g;

    # Replace \0 with ".*"
    $regex =~ s/\0/.*/g;

    return "^$regex\$";
}
#
# END: CLASS: Section
########################################################################

########################################################################
# CLASS: Section::Group
#
package Section::Group;
use base qw(Section);
use Carp;

use constant REQ_ATTRIBUTES	=> qw(Users);

sub Parameters {
    my $self		= shift;
    my $parameter_ref	= shift;

    $self->SUPER::Parameters( $parameter_ref, \@{[REQ_ATTRIBUTES]} );
}

sub Users {
    my $self		= shift;
    my $users		= shift;

    if ( defined $users ) {
	my @users = split /[\s,]+/, $users;
	$self->{USERS} = \@users;
    }

    my @users = @{ $self->{USERS} };
    return wantarray ? @users : \@users;
}
#
# END: CLASS: Section::Group
########################################################################

########################################################################
# CLASS: Section::File
#
package Section::File;
use base qw(Section);
use Carp;

use constant REQ_ATTRIBUTES 	=> qw(Match Users Access);
use constant VALID_CASES	=> qw(match ignore);
use constant VALID_ACCESSES	=> qw(read-only read-write add-only no-delete no-add);

sub Parameters {
    my $self		= shift;
    my $parameter_ref	= shift;

    $self->SUPER::Parameters( $parameter_ref, \@{[REQ_ATTRIBUTES]} );
}

sub Match {
    my $self		= shift;
    my $match		= shift;

    if ( defined $match ) {
	$self->{MATCH} = $match;
    }

    return $self->{MATCH};
}

sub Access {
    my $self		= shift;
    my $access		= shift;

    if ( defined $access ) {
	$access = lc $access;
	my %valid_accesses;
	map { $valid_accesses{lc $_} = 1 } +VALID_ACCESSES;
	if ( not exists $valid_accesses{$access} ) {
	    croak qq(Invalid File access "$access");
	}
	$self->{ACCESS} = $access;
    }

    return $self->{ACCESS};
}

sub File {
    my $self		= shift;
    my $glob		= shift;

    if ( not defined $glob ) {
	croak qq(Matching glob file pattern required);
    }

    my $match = Section::glob2regex( $glob );
    return $self->Match( $match );
}

sub Case {
    my $self		= shift;
    my $case		= shift;

    if ( defined $case ) {
	$case = lc $case;
	my %valid_cases;
	map { $valid_cases{lc $_} = 1 } +VALID_CASES;
	if ( not exists $valid_cases{$case} ) {
	    croak qq(Invalid case "$case" passed to method);
	}
	$self->{CASE} = $case;
    }
    return $self->{CASE};
}

sub Users {
    my $self		= shift;
    my $users		= shift;

    if ( defined $users ) {
	my @users = split /[\s,]+/, $users;
	$self->{USERS} = \@users;
    }

    my @users = @{ $self->{USERS} };
    return wantarray ? @users : \@users;
}
#
# END: CLASS Section::Group
########################################################################

########################################################################
# CLASS: Section::Property
#
package Section::Property;
use Carp;
use base qw(Section);

use constant REQ_PARAMETERS	=> qw(Match Property Value Type);
use constant VALID_TYPES	=> qw(string number regex);
use constant VALID_CASES	=> qw(match ignore);

sub Parameters {
    my $self		= shift;
    my $parameter_ref	= shift;

    $self->SUPER::Parameters( $parameter_ref, \@{[REQ_PARAMETERS]} );
}

sub Match {
    my $self		= shift;
    my $match		= shift;

    if ( defined $match ) {
	$self->{MATCH} = $match;
    }
    return $self->{MATCH};
}

sub File {
    my $self		= shift;
    my $glob		= shift;

    if ( not defined $glob ) {
	croak qq(Method is only for setting not fetching);
    }

    my $match = Section::glob2regex($glob);
    return $self->Match( $match );
}

sub Case {
    my $self		= shift;
    my $case		= shift;

    if ( defined $case ) {
	my %valid_cases;
	my $case = lc $case;
	map { $valid_cases{lc $_} = 1 } @{[VALID_CASES]};
	if ( not exists $valid_cases{$case} ) {
	    croak qq(Invalid case "$case");
	}
	$self->{CASE} = $case;
    }
    return $self->{CASE};
}

sub Property {
    my $self		= shift;
    my $property	= shift;

    if ( defined $property ) {
	$self->{PROPERTY} = $property;
    }
    return $self->{PROPERTY};
}

sub Value {
    my $self		= shift;
    my $value		= shift;

    if ( defined $value ) { 
	$self->{VALUE} = $value;
    }
    return $self->{VALUE};
}

sub Type {
    my $self		= shift;
    my $type		= shift;

    if ( defined $type ) {
	my $type = lc $type;
	my %valid_types;
	map { $valid_types{lc $_} = 1 } +VALID_TYPES;
	if ( not exists $valid_types{$type} ) {
	    croak qq(Invalid type of "$type" Property type passed);
	}
	$self->{TYPE} = $type;
    }
    return $self->{TYPE};
}
#
# END: Class: Section::Property
########################################################################

########################################################################
# CLASS: Section::Revprop
#
package Section::Revprop;
use Carp;
use base qw(Section);

use constant REQ_PARAMETERS	=> qw(Property Value Type);
use constant VALID_TYPES	=> qw(string number regex);
use constant VALID_CASES	=> qw(match ignore);

sub Parameters {
    my $self		= shift;
    my $parameter_ref	= shift;

    $self->SUPER::Parameters( $parameter_ref, \@{[REQ_PARAMETERS]} );
}

sub Case {
    my $self		= shift;
    my $case		= shift;

    if ( defined $case ) {
	my %valid_cases;
	my $case = lc $case;
	map { $valid_cases{lc $_} = 1 } @{[VALID_CASES]};
	if ( not exists $valid_cases{$case} ) {
	    croak qq(Invalid case "$case");
	}
	$self->{CASE} = $case;
    }
    return $self->{CASE};
}

sub Property {
    my $self		= shift;
    my $property	= shift;

    if ( defined $property ) {
	$self->{PROPERTY} = $property;
    }
    return $self->{PROPERTY};
}

sub Value {
    my $self		= shift;
    my $value		= shift;

    if ( defined $value ) { 
	$self->{VALUE} = $value;
    }
    return $self->{VALUE};
}

sub Type {
    my $self		= shift;
    my $type		= shift;

    if ( defined $type ) {
	my $type = lc $type;
	my %valid_types;
	map { $valid_types{lc $_} = 1 } +VALID_TYPES;
	if ( not exists $valid_types{$type} ) {
	    croak qq(Invalid type of "$type" Property type passed);
	}
	$self->{TYPE} = $type;
    }
    return $self->{TYPE};
}
#
# END: Class: Section::Revprop
########################################################################

########################################################################
# Class: Section::Ban
# 
package Section::Ban;
use base qw(Section);

use Carp;

use constant REQ_PARAMETERS	=> qw(Match);
use constant VALID_CASES	=> qw(match ignore);

sub Parameters {
    my $self		= shift;
    my $parameter_ref	= shift;

    $self->SUPER::Parameters( $parameter_ref, \@{[REQ_PARAMETERS]} );
}

sub File {
    my $self		= shift;
    my $glob		= shift;

    my $match = Section::glob2regex( $glob );
    $self->Match( $match );
}

sub Match {
    my $self		= shift;
    my $match		= shift;

    if ( defined $match ) {
	$self->{MATCH} = $match;
    }
    return $self->{MATCH};
}

sub Case {
    my $self		= shift;
    my $case		= shift;

    if ( defined $case ) {
	$case = lc $case;
	my %valid_cases;
	map { $valid_cases{lc $_} = 1 } +VALID_CASES;
	if ( not exists $valid_cases{$case} ) {
	    croak qq(Invalid case "$case" passed to method);
	}
	$self->{CASE} = $case;
    }
    return $self->{CASE};
}
#
# END: Class Section::Ban
########################################################################

########################################################################
# Class Section::Ldap
#
package Section::Ldap;
use Carp;
use base qw(Section);

use constant REQ_ATTRIBUTES	=> qw(ldap);

use constant {
    DEFAULT_NAME_ATTR	=> "sAMAccountName",
    DEFAULT_GROUP_ATTR	=> "memberOf",
    DEFAULT_TIMEOUT	=> 5,
};

BEGIN {
    eval { require Net::LDAP; };
    our $ldap_available = 1 if not $@;
}
our $ldap_available;

sub Parameters {
    my $self 		= shift;
    my $parameter_ref	= shift;

    if ( not $ldap_available ) {
	croak qq(You need to install the Perl module "Net::LDAP" to use LDAP groups);
    }

    $self->SUPER::Parameters ( $parameter_ref, \@{[REQ_ATTRIBUTES]} );
}

sub Ldap {
    my $self		= shift;

    if ( not $self->Description ) {
	croak qq(Missing description which contains the LDAP server list);
    }

    my @ldaps = split /[\s,]+/, $self->Desciption;	
    return wantarray ? @ldaps : \@ldaps;
}

sub Username_attr {
    my $self		= shift;
    my $username_attr	= shift;

    if ( defined $username_attr ) {
	$self->{USER_NAME_ATTR} = $username_attr;
    }

    if ( not exists $self->{USER_NAME_ATTR} ) {
	$self->{USER_NAME_ATTR} = DEFAULT_NAME_ATTR;
    }
    return $self->{LDAP_ACCT_ATTR};
}

sub Group_attr {
    my $self		= shift;
    my $group_attr	= shift;

    if ( defined $group_attr ) {
	$self->{GROUP_ATTR} = $group_attr;
    }
    if ( not exists $self->{GROUP_ATTR} ) {
	$self->{GROUP_ATTR} = DEFAULT_GROUP_ATTR;
    }
    return $self->{GROUP_ATTR};
}

sub User_dn {
    my $self		= shift;
    my $user_dn		= shift;

    if ( defined $user_dn ) {
	$self->{USER_DN} = $user_dn;
    }
    return $self->{USER_DN};
}

sub Password {
    my $self		= shift;
    my $password	= shift;

    if ( defined $password ) {
	$self->{PASSWORD} = $password;
    }
    return $self->{PASSWORD};
}

sub Search_base {
    my $self		= shift;
    my $search_base	= shift;

    if ( defined $search_base ) {
	$self->{SEARCH_BASE} = $search_base;
    }
    return $self->{SEARCH_BASE};
}

sub Timeout {
    my $self		= shift;
    my $timeout		= shift;

    if ( defined $timeout ) {
	if ( $timeout =~ /^\d+$/ ) {
	    croak qq(Timeout value for ldap server must be an integer);
	}
	$self->{TIMEOUT} = $timeout;
    }

    if ( not exists $self->{TIMEOUT} ) {
	$self->{TIMEOUT} = DEFAULT_TIMEOUT;
    }
    return $self->{TIMEOUT};
}

sub Ldap_Groups {
    my $self		= shift;
    my $user		= shift;

    my $ldap_servers	= $self->Ldap;
    my $user_dn		= $self->User_dn;
    my $password	= $self->Password;
    my $search_base	= $self->Search_base;
    my $timeout		= $self->Timeout;

    my $username_attr	= $self->Username_attr;
    my $group_attr	= $self->Group_attr;

    if ( not defined $user ) {
	croak qq(Need to pass in a user name);
    }

    #
    # Create LDAP Object
    #
    my $ldap = Net::LDAP->new( $ldap_servers, timeout => $timeout, onerror => "die" );
    if ( not defined $ldap ) {
	croak qq(Could not connect to LDAP servers:)
	    . join ", ", @{ $ldap } . qq( Timeout = $timeout );
    }
    #
    # Try a bind
    #
    eval {
	if ( $user_dn and $password ) {
	    $ldap->bind( $user_dn, password => $password );
	}
	elsif ( $user_dn and not $password ) {
	    $ldap->bind( $user_dn );
	}
	else {
	    $ldap->bind;
	}
    };
    if ( $@ ) {
	no warnings qw(uninitialized);
	croak qq(Could not "bind" to LDAP server.) 
	    . qq( User DN: "$user_dn" Password: "$password");
    }

    #
    # Search
    #

    my $search;
    eval {
	if ( $search_base ) {
	    $search = $ldap->search(
		basename => $search_base,
		filter => "($username_attr=$user)",
	    );
	}
	else {
	    $search = $ldap->search(
		filter => "($username_attr=$user)",
	    );
	}
    };
    if ( $@ ) {
	croak qq(Search of LDAP tree failed);
    }

    #
    # Get the Entry
    #
    my $entry = $search->pop_entry;	#Should only return a single entry
    if ( undef $entry ) {
	croak qq(Could not locate "$user" with attribute "$username_attr".);
    }

    #
    # Get the attribute of that entry
    #

    my @groups;
    for my $group ( $entry->get_value( $group_attr ) ) {
	$group =~ s/cn=(.+?),.*/\L$1\U/i;  	#Just the "CN" value
	push @groups, $group;
    }
    return wantarray ? @groups : \@groups;
}
