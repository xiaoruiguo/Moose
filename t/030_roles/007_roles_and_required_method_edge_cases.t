#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 19;
use Test::Exception;

=pod

NOTE:
A fair amount of these tests will likely be irrelevant 
once we have more fine grained control over the class
building process. A lot of the edge cases tested here
are actually related to class construction order and 
not any real functionality.
- SL

=cut

BEGIN {
    use_ok('Moose');
    use_ok('Moose::Role');    
}

=pod

Role which requires a method implemented 
in another role as an override (it does 
not remove the requirement)

=cut

{
    package Role::RequireFoo;
    use strict;
    use warnings;
    use Moose::Role;
    
    requires 'foo';
    
    package Role::ProvideFoo;
    use strict;
    use warnings;
    use Moose::Role;
    
    ::lives_ok {
        with 'Role::RequireFoo';
    } '... the required "foo" method will not exist yet (but we will live)';
    
    override 'foo' => sub { 'Role::ProvideFoo::foo' };    
}

is_deeply(
    [ Role::ProvideFoo->meta->get_required_method_list ], 
    [ 'foo' ], 
    '... foo method is still required for Role::ProvideFoo');

=pod

Role which requires a method implemented 
in the consuming class as an override. 
It will fail since method modifiers are 
second class citizens.

=cut

{
    package Class::ProvideFoo::Base;
    use Moose;

    sub foo { 'Class::ProvideFoo::Base::foo' }
        
    package Class::ProvideFoo::Override1;
    use Moose;
    
    extends 'Class::ProvideFoo::Base';
    
    ::lives_ok {
        with 'Role::RequireFoo';
    } '... the required "foo" method will be found in the superclass';
    
    override 'foo' => sub { 'Class::ProvideFoo::foo' };    
    
    package Class::ProvideFoo::Override2;
    use Moose;
    
    extends 'Class::ProvideFoo::Base';
    
    override 'foo' => sub { 'Class::ProvideFoo::foo' };     
    
    ::dies_ok {
        with 'Role::RequireFoo';
    } '... the required "foo" method exists, but it is an override (and we will die)';

}

=pod

Now same thing, but with a before 
method modifier.

=cut

{
    package Class::ProvideFoo::Before1;
    use Moose;
    
    extends 'Class::ProvideFoo::Base';
    
    ::lives_ok {
        with 'Role::RequireFoo';
    } '... the required "foo" method will be found in the superclass';
    
    before 'foo' => sub { 'Class::ProvideFoo::foo:before' };    
    
    package Class::ProvideFoo::Before2;
    use Moose;
    
    extends 'Class::ProvideFoo::Base';
    
    before 'foo' => sub { 'Class::ProvideFoo::foo:before' };     
    
    ::dies_ok {
        with 'Role::RequireFoo';
    } '... the required "foo" method exists, but it is a before (and we will die)';    
    
    package Class::ProvideFoo::Before3;
    use Moose;
    
    extends 'Class::ProvideFoo::Base';
    
    ::lives_ok {
        with 'Role::RequireFoo';
    } '... the required "foo" method will not exist yet (and we will die)';
    
    sub foo { 'Class::ProvideFoo::foo' }
    before 'foo' => sub { 'Class::ProvideFoo::foo:before' };    
    
    package Class::ProvideFoo::Before4;
    use Moose;
    
    extends 'Class::ProvideFoo::Base';
    
    sub foo { 'Class::ProvideFoo::foo' }    
    before 'foo' => sub { 'Class::ProvideFoo::foo:before' };     

    ::isa_ok(__PACKAGE__->meta->get_method('foo'), 'Class::MOP::Method::Wrapped');
    ::is(__PACKAGE__->meta->get_method('foo')->get_original_method->package_name, __PACKAGE__, 
    '... but the original method is from our package');
    
    ::lives_ok {
        with 'Role::RequireFoo';
    } '... the required "foo" method exists in the symbol table (and we will live)'; 
    
    package Class::ProvideFoo::Before5;
    use Moose;
    
    extends 'Class::ProvideFoo::Base';
       
    before 'foo' => sub { 'Class::ProvideFoo::foo:before' };   
    
    ::isa_ok(__PACKAGE__->meta->get_method('foo'), 'Class::MOP::Method::Wrapped');
    ::isnt(__PACKAGE__->meta->get_method('foo')->get_original_method->package_name, __PACKAGE__, 
    '... but the original method is not from our package');      
    
    ::dies_ok {
        with 'Role::RequireFoo';
    } '... the required "foo" method exists, but it is a before wrapping the super (and we will die)';       
}    

=pod

Now same thing, but with a method from an attribute
method modifier.

=cut

{
    
    package Class::ProvideFoo::Attr1;
    use Moose;
    
    extends 'Class::ProvideFoo::Base';
    
    ::lives_ok {
        with 'Role::RequireFoo';
    } '... the required "foo" method will be found in the superclass (but then overriden)';
    
    has 'foo' => (is => 'ro');
    
    package Class::ProvideFoo::Attr2;
    use Moose;
    
    extends 'Class::ProvideFoo::Base';
    
    has 'foo' => (is => 'ro');     
    
    ::dies_ok {
        with 'Role::RequireFoo';
    } '... the required "foo" method exists, but it is a before (and we will die)';    
}    

# ...
# a method required in a role, but then 
# implemented in the superclass (as an 
# attribute accessor too)
    
{
    package Foo::Class::Base;
    use Moose;
    
    has 'bar' =>  ( 
        isa     => 'Int', 
        is      => 'rw', 
        default => sub { 1 }
    );
}
{
    package Foo::Role;
    use Moose::Role;
    
    requires 'bar';
    
    has 'foo' => ( 
        isa     => 'Int', 
        is      => 'rw', 
        lazy    => 1, 
        default => sub { (shift)->bar + 1 } 
    );
}
{
    package Foo::Class::Child;
    use Moose;
    extends 'Foo::Class::Base';
    
    ::dies_ok {       
        with 'Foo::Role';
    } '... our role combined successfully';
}

# a method required in a role and implemented in a superclass, with a method
# modifier in the subclass.  this should live, but dies in 0.26 -- hdp,
# 2007-10-11

{
    package Bar::Class::Base;
    use Moose;

    sub bar { "hello!" }
}
{
    package Bar::Role;
    use Moose::Role;
    requires 'bar';
}
{
    package Bar::Class::Child;
    use Moose;
    extends 'Bar::Class::Base';
    after bar => sub { "o noes" };
    # technically we could run lives_ok here, too, but putting it into a
    # grandchild class makes it more obvious why this matters.
}
{
    package Bar::Class::Grandchild;
    use Moose;
    extends 'Bar::Class::Child';
    ::lives_ok {
        with 'Bar::Role';
    } 'required method exists in superclass as non-modifier, so we live';
}
