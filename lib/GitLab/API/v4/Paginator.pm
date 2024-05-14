package GitLab::API::v4::Paginator;
our $VERSION = '0.27';

=encoding utf8

=head1 NAME

GitLab::API::v4::Paginator - Iterate through paginated GitLab v4 API records.

=head1 DESCRIPTION

There should be no need to create objects of this type
directly, instead use L<GitLab::API::v4/paginator> which
simplifies things a bit.

=cut

use Carp qw( croak );
use Types::Common::String -types;
use Types::Standard -types;

use Moo;
use strictures 2;
use namespace::clean;

=head1 REQUIRED ARGUMENTS

=head2 method

The name of the method subroutine to call on the L</api> object
to get records from.

This method must accept a hash ref of parameters as the last
argument, adhere to the C<page> and C<per_page> parameters, and
return an array ref.

=cut

has method => (
    is       => 'ro',
    isa      => NonEmptySimpleStr,
    required => 1,
);

=head2 api

The L<GitLab::API::v4> object.

=cut

has api => (
    is       => 'ro',
    isa      => InstanceOf[ 'GitLab::API::v4' ],
    required => 1,
);

=head1 OPTIONAL ARGUMENTS

=head2 args

The arguments to use when calling the L</method>, the same arguments
you would use when you call the method yourself on the L</api>
object, minus the C<\%params> hash ref.

=cut

has args => (
    is      => 'ro',
    isa     => ArrayRef,
    default => sub{ [] },
);

=head2 params

The C<\%params> hash ref argument.

=cut

has params => (
    is      => 'ro',
    isa     => HashRef,
    default => sub{ {} },
);

has _next_params => (
    is      => 'rw',
    isa     => HashRef,
    default => sub{ {} },
);

=head1 METHODS

=cut

has _records => (
    is       => 'rw',
    init_arg => undef,
    default  => sub{ [] },
);

has _page => (
    is       => 'rw',
    init_arg => undef,
    default  => 0,
);

has _last_page => (
    is       => 'rw',
    init_arg => undef,
    default  => 0,
);

=head2 next_page

    while (my $records = $paginator->next_page()) { ... }

Returns an array ref of records for the next page.

To use keyset pagination pagination=>'keyset' must be set
in params hash

=cut

sub next_page {
    my ($self) = @_;

    return if $self->_last_page();

    my $page;
    my $params   = $self->params();
    # Don't allow cursor to be directly passed in
    delete $params->{'cursor'};

    # if keyset pagination
    my $pagination = $params->{'pagination'};
    my $keyset = (defined $pagination && $pagination eq 'keyset') ? 1 : 0;

    my $method = $self->method();
    # As of Gitlab v17.0 'users'endpoint only uses keyset pagination
    $keyset = 1 if ($method eq 'users' && ! $keyset);

    my $per_page = $params->{per_page} || 20;

    if ($keyset) {
        my $next_params = $self->_next_params();
        $params = {
            'order_by'   => 'id',
            'sort'       => 'asc',
            'per_page'   => $per_page,
            %$params,
            'pagination' => 'keyset',
            %$next_params,
        };
    } else {
        $page     = $self->_page() + 1;
        $params = {
            %$params,
            page     => $page,
            per_page => $per_page,
        };
    }

    my ($headers,$records) = $self->api->$method(
        @{ $self->args() },
        $params,
    );

    croak("The $method method returned a non array ref value")
        if ref($records) ne 'ARRAY';

    if ($keyset) {
        $self->_next_link_params($headers)
    } else {
        $self->_page( $page );
    }
    $self->_last_page( 1 ) if @$records < $per_page;
    $self->_records( [ @$records ] );

    return if !@$records;

    return $records;
}

=head2 _next_link_params

  Sets _next_params hash, from the params returned in the next link,
  when using pagination='keyset'

=cut

sub _next_link_params {
    my ($self,$headers) = @_;
    my $links = $headers->{'link'};
    return undef if ! $links;
    return undef if ! ($links =~ m/([^<]*)>; rel="next"/);
    my $nextLink = $1;
    my $params = {};
    my ($url,$paramStr) = split('\?',$nextLink);
    return undef if (! $paramStr);
    my @paramList = split("&",$paramStr);
    foreach my $param (@paramList) {
        my ($key,$val) = split("=",$param);
        $params->{$key} = $val;
    }
    $self->_next_params($params);
    return 1;
}

=head2 next

    while (my $record = $paginator->next()) { ... }

Returns the next record in the current page.  If all records have
been exhausted then L</next_page> will automatically be called.
This way if you want to ignore pagination you can just call C<next>
over and over again to walk through all the records.

=cut

sub next {
    my ($self) = @_;

    my $records = $self->_records();
    return shift(@$records) if @$records;

    return if $self->_last_page();

    $self->next_page();

    $records = $self->_records();
    return shift(@$records) if @$records;

    return;
}

=head2 all

    my $records = $paginator->all();

This is just an alias for calling L</next_page> over and over
again to build an array ref of all records.

=cut

sub all {
    my ($self) = @_;

    $self->reset();

    my @records;
    while (my $page = $self->next_page()) {
        push @records, @$page;
    }

    return \@records;
}

=head2 reset

    $paginator->reset();

Reset the paginator back to its original state on the first page
with no records retrieved yet.

=cut

sub reset {
    my ($self) = @_;
    $self->_records( [] );
    $self->_page( 0 );
    $self->_next_params( {} );
    $self->_last_page( 0 );
    return;
}

1;
__END__

=head1 SUPPORT

See L<GitLab::API::v4/SUPPORT>.

=head1 AUTHORS

See L<GitLab::API::v4/AUTHORS>.

=head1 LICENSE

See L<GitLab::API::v4/LICENSE>.

=cut

