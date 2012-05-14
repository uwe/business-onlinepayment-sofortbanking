package Business::OnlinePayment::Sofortbanking;

our $VERSION = 0.001;

use strict;
use warnings;

use base 'Business::OnlinePayment';

use Digest::SHA;
use URI;


my @SUPPORTED_TYPES      = qw/ECHECK/;
my @SUPPORTED_ACTIONS    = ('Authorization Only');
my @SUPPORTED_CURRENCIES = qw/EUR CHF GBP/;
my @SUPPORTED_LANGUAGES  = qw/DE EN NL FR/;

my %SUPPORTED_TYPE       = map { $_ => 1 } @SUPPORTED_TYPES;
my %SUPPORTED_ACTION     = map { $_ => 1 } @SUPPORTED_ACTIONS;
my %SUPPORTED_CURRENCY   = map { $_ => 1 } @SUPPORTED_CURRENCIES;
my %SUPPORTED_LANGUAGE   = map { $_ => 1 } @SUPPORTED_LANGUAGES;

my %PARAMETER = (
    user_id               => {check => \&_number, required => 1},
    project_id            => {check => \&_number, required => 1},
    amount                => {check => \&_amount, required => 1},
    reason_1              => {max_length => 27},
    reason_2              => {max_length => 27},
    user_variable_0       => {max_length => 255},
    user_variable_1       => {max_length => 255},
    user_variable_2       => {max_length => 255},
    user_variable_3       => {max_length => 255},
    user_variable_4       => {max_length => 255},
    user_variable_5       => {max_length => 255},
    sender_bank_code      => {max_length => 30},
    sender_account_number => {max_length => 30},
    sender_holder         => {max_length => 27},
    sender_country_id     => {check => \&_country},
    currency_id           => {check => \&_currency, required => 1},
    language_id           => {check => \&_language},
    timeout               => {check => \&_number},
    project_password      => {required => 1},
);

my %PARAMETER_MAP = (
    description    => 'reason_1',
    currency       => 'currency_id',
    account_number => 'sender_account_number',
    routing_code   => 'sender_bank_code',
    account_name   => 'sender_holder',
);

my @HASH_ORDER = qw/
    user_id
    project_id
    sender_holder
    sender_account_number
    sender_bank_code
    sender_country_id
    amount
    currency_id
    reason_1
    reason_2
    user_variable_0
    user_variable_1
    user_variable_2
    user_variable_3
    user_variable_4
    user_variable_5
    project_password
/;

my %DEFAULT = (
    server => 'www.sofort.com',
    path   => '/payment/start',
    port   => 443,
    type   => $SUPPORTED_TYPES[0],
    action => $SUPPORTED_ACTIONS[0],
);


sub _info {
    return {
        info_compat       => '0.01',
        gateway_name      => 'Sofortbanking',
        gateway_url       => 'http://www.sofort.com/',
        module_version    => $VERSION,
        supported_types   => \@SUPPORTED_TYPES,
        token_support     => 0,
        test_transaction  => 0,
        supported_actions => \@SUPPORTED_ACTIONS,
    };
}

sub set_defaults {
    my ($self, %arg) = @_;

    # set defaults
    while (my ($name, $default) = each %DEFAULT) {
        $self->{$name} ||= $default;
    }

    $self->build_subs(qw/popup_url/);
}

sub submit {
    my ($self) = @_;

    die 'test mode not supported' if $self->test_transaction;

    my %content = $self->content;

    # apply default parameters
    $content{$_} ||= $self->{$_} foreach (keys %DEFAULT);

    die 'unsupported type - only: ' . join(', ', @SUPPORTED_TYPES)
        unless $SUPPORTED_TYPE{$content{type}};

    die 'unsupported action - only: ' . join(', ', @SUPPORTED_ACTIONS)
        unless $SUPPORTED_ACTION{$content{action}};

    # parameter mapping
    while (my ($old_field, $new_field) = each %PARAMETER_MAP) {
        $content{$new_field} ||= $content{$old_field};
    }
    # standard processor fields
    $content{user_id} ||= $content{login};

    # parameter checking
    my %param = ();
    while (my ($field, $param) = each %PARAMETER) {
        my $value = $content{$field};
        if ($param->{required}) {
            die "field '$field' is required" unless $value;
        }
        if ($param->{check}) {
            my $error = $param->{check}->($value);
            die "field '$field' $error" if $error;
        }
        if ($param->{max_length} and length($value) > $param->{max_length}) {
            die "field '$field' is too long (max. $param->{max_length})";
        }
        $param{$field} = $value;
    }

    # calculate hash value
    my @hash_data = map { $content{$_} || '' } @HASH_ORDER;
    $param{hash} = Digest::SHA::sha256_hex(join('|', @hash_data));

    # construct URL
    my $url = URI->new('https://' . $self->server . $self->path);
    $url->port($self->port);
    $url->query_form(%param);
    $self->popup_url($url . '');

    $self->is_success(1);

    return 1;
}


# field validation utilities
sub _number {
    my ($value) = @_;
    return 'is not a number' if $value and $value !~ /^\d+$/;
    return;
}

sub _amount {
    my ($value) = @_;
    return 'is not a valid amount (xxx.xx)' if $value and $value !~ /^\d+\.\d\d$/;
    return 'is too small (minimum 0.10)' if $value < 0.10;
    return;
}

sub _country {
    my ($value) = @_;
    return 'is not a valid country (XX)' if $value and $value !~ /^[A-Z]{2}$/;
    return;
}

sub _currency {
    my ($value) = @_;
    return 'is not a valid currency (' . join('|', @SUPPORTED_CURRENCIES) . ')'
        if $value and not $SUPPORTED_CURRENCY{$value};
    return;
}

sub _language {
    my ($value) = @_;
    return 'is not a valid language (' . join('|', @SUPPORTED_LANGUAGES) . ')'
        if $value and not $SUPPORTED_LANGUAGE{$value};
    return;
}


1;

__END__

=head1 NAME

Business::OnlinePayment::Sofortbanking - sofort.com sofortbanking/sofortueberweisung

=head1 SYNOPSIS

  use Business::OnlinePayment;

  my $tx = Business::OnlinePayment->new('Sofortbanking');

  $tx->content(
      user_id               => 12345,
      project_id            => 123456,
      project_password      => 'secret',
      amount                => '2.75',
      currency_id           => 'EUR',
      reason_1              => 'Invoice: 1234',
      reason_2              => 'Order date: 01/01/2012',
      sender_holder         => 'John Doe',
      sender_bank_code      => 88888888,       # demo bank
      sender_account_number => 12345678,
      sender_country_id     => 'DE',
  );

  $tx->submit;

  if ($tx->is_success) {
      # redirect user (so that he can make the credit transfer)
      my $url = $tx->popup_url;
  } else {
      # does not happen - the code dies if parameters are missing
  }

=head1 DESCRIPTION

This module is the backend for sofort.com (sofortbanking/sofortueberweisung).
It is a direct payment method (credit transfer).

To complete the payment process, you have to redirect the user to sofort.com.
This modules constructs the necessary URL (L<popup_url>). If the transaction
succeeds, the user is redirected to your "success link". If it fails, the
"abort link" is choosen. You can adjust these settings in the admin section.

=head1 CONSTRUCTOR

You have the specify the following three parameters:

=over 4

=item user_id

Your customer number.

=item project_id

Your project number.

=item project_password

Your project password. You can generate one in the admin section for your
project ("Extended settings" / "Passwords and hash algorithm"). Be sure to
set the hash algorithm to C<SHA256>.

=back

=head1 METHODS

=head2 popup_url

After C<submit> this contains the URL to which you have to redirect the user.

=cut
