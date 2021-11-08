package ColiRich;
use v5.14.1;

use parent qw(Exporter);
our @EXPORT = qw(getConcept trustedMapping getMappings);

use JSON::API;
use List::Util qw(any);

my $defaultTrust = { type => [ 'exactMatch', 'narrowMatch' ] };

our %APIOPT = ( debug => 0, ssl_opts => { verify_hostname => 0 } );

sub getConcept {
    my ( $voc, %query ) = @_;

    die "missing notation" unless $query{notation} or $query{uri};

    my $hash = join ' ', map { ( $_, $query{$_} ) } sort keys %query;

    state %cache;
    unless ( exists $cache{$hash} ) {

        my $api = JSON::API->new( $voc->{API}, %APIOPT );
        my $res = $api->get( 'data', { voc => $voc->{uri}, %query } );
        if ( $api->was_success && ref $res ) {
            $cache{$hash} = $res->[0];
        }
        else {
            $cache{$hash} = undef;
            my $id = $query{notation} // $query{uri};
            warn "unknown " . $voc->{notation}[0] . ": $id\n";
        }
    }

    return $cache{$hash};
}

sub getMappings {
    my ( $from, $to, $notation, $trust ) = @_;

    # TODO: include types for selected concordances
    my @types = map { "http://www.w3.org/2004/02/skos/core#$_" }
      @{ $trust->{type} || $defaultTrust->{type} };

    my $api = JSON::API->new( 'http://coli-conc.gbv.de/api/mappings', %APIOPT );
    my $mappings = $api->get(
        '',
        {
            from       => $notation,
            fromSchme  => $from->{uri},
            toScheme   => $to->{uri},
            properties => 'annotations,creator',
            type       => join( '|', @types ),
        }
    );

    return grep { trustedMapping( $_, $trust ) } @$mappings;
}

sub trustedMapping {
    my ( $mapping, $trust ) = @_;

    my $ann = $mapping->{annotations} || [];

    # trust all confirmed mappings
    return 1 if any { $_->{motivation} eq 'moderating' } @$ann;

    # never trust downvoted mappings
    # (TODO: only if downvoted by known account)
    return 0
      if any { $_->{motivation} eq 'assessing' and $_->{bodyValue} eq "-1" }
    @$ann;

    # TODO: check concordance

    my %account = map { ( $_ => 1 ) } @{ $trust->{account} || [] };

    if (%account) {

        # trust mappings by known accounts
        return any { $account{ $_->{uri} } } @{ $mapping->{creator} || [] };
    }
    else {
        # trust all mappings
        return 1;
    }
}

1;
