package Net::Zabbix;

use strict;
use JSON::XS;
use LWP::UserAgent;

sub new {
    my ($class, $url, $user, $password) = @_;

    my $ua = LWP::UserAgent->new;
    $ua->agent("Net::Zabbix");

    my $req = HTTP::Request->new(POST => "$url/api_jsonrpc.php");
    $req->content_type('application/json-rpc');

    $req->content(encode_json( {
        jsonrpc => "2.0",
        method => "user.authenticate",
        params => {
            user => $user,
            password => $password,
        },
        id => 1,
    }));

    my $res = $ua->request($req);

    unless ($res->is_success) {
      die "Can't connect to Zabbix" . $res->status_line;
    }

    my $auth = decode_json($res->content)->{'result'};

    return bless {
        UserAgent => $ua,
        Request   => $req,
        Count     => 1,
        Auth      => $auth,
    }, $class;
}

sub ua {
    return shift->{'UserAgent'};
}

sub req {
    return shift->{'Request'};
}

sub auth {
    return shift->{'Auth'};
}

sub next_id {
    return ++shift->{'Count'};
}

sub get {
    my ($self, $object, $params) = @_;

    my $req = $self->req;
    $req->content(encode_json( {
        jsonrpc => "2.0",
        method => "$object.get",
        params => $params,
        auth => $self->auth,
        id => $self->next_id,
    }));

    my $res = $self->ua->request($req);

    unless ($res->is_success) {
      die "Can't connect to Zabbix" . $res->status_line;
    }

    return decode_json($res->content);
}

#"post" and "update" are new methods that didn't exist in Zabbix.pm original version at
#https://github.com/sjohnston/Net-Zabbix/blob/master/lib/Net/Zabbix.pm
#copy & paste the "get" method, rename, and done
#check if the method exist at zabbix api documentation
#http://www.zabbix.com/documentation/1.8/api/item
sub post{
    my ($self, $object, $params) = @_;

    my $req = $self->req;
    $req->content(encode_json( {
        jsonrpc => "2.0",
        method => "$object.create",
        params => $params,
        auth => $self->auth,
        id => $self->next_id,
    }));

    my $res = $self->ua->request($req);

    unless ($res->is_success) {
      die "Can't connect to Zabbix" . $res->status_line;
    }

    return decode_json($res->content);
}

sub update{
    my ($self, $object, $params) = @_;

    my $req = $self->req;
    $req->content(encode_json( {
        jsonrpc => "2.0",
        method => "$object.update",
        params => $params,
        auth => $self->auth,
        id => $self->next_id,
    }));

    my $res = $self->ua->request($req);

    unless ($res->is_success) {
      die "Can't connect to Zabbix" . $res->status_line;
    }

    return decode_json($res->content);
}


1;
