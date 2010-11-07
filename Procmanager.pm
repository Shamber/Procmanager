package Procmanager;
use Wx qw(wxDefaultPosition wxDefaultSize wxDEFAULT_FRAME_STYLE);
use strict;
use warnings;
use Wx::Perl::ProcessStream qw( :everything );
use base qw(Wx::Frame);
my $self;

sub new {
    my $check = shift;
    my %hash = @_;
    my $proto = ref( $check ) || $check;
    my $parent = undef;
    my $id     = -1;
    my $title  = "";
    my $pos    = wxDefaultPosition;
    my $size   = wxDefaultSize;
    my $name   = "u" ;

# begin wxGlade: MyDialog::new
    return $self if (defined $self);
    my $style = wxDEFAULT_FRAME_STYLE;

    $self = $proto->SUPER::new( $parent, $id, $title, $pos, $size, $style,$name);
    #unless (defined $self->{load}){
    #    bless ($self,$proto);
    #    $self->{load} =1;
    #}
    EVT_WXP_PROCESS_STREAM_STDOUT    ( $self, \&evt_stdout );
    EVT_WXP_PROCESS_STREAM_STDERR    ( $self, \&evt_error);
    EVT_WXP_PROCESS_STREAM_EXIT      ( $self, \&evt_exit  );
    
    return $self;
}

sub StartNewProc{
    my $self = shift;
    my %hash = @_;
    return "Select command" unless defined $hash{command};
    $hash{name} = "Proc" unless defined $hash{name};
    $self->{proc}->{$hash{name}}->{stdout} = $hash{stdout} if defined $hash{stdout};
    $self->{proc}->{$hash{name}}->{exit} = $hash{exit} if defined $hash{stdout};
    $self->{proc}->{$hash{name}}->{error} = $hash{error} if defined $hash{stdout};
    $self->{proc}->{$hash{name}}->{combuf} =[]; #буффер куда помещаем команды для выполнения $self->{"test"}->[combuf] ={id}-> @command
    $self->{proc}->{$hash{name}}->{retevtbuf} =[]; # хеш который будет содержать информацию о идентификаторе и процедуре, $self->{"test"}->[retevtbuf] ={id}-> @command
    unless($self->{proc}->{$hash{name}}->{proc} = Wx::Perl::ProcessStream::Process->new($hash{command}, $hash{name}, $self)->Run){ 
        return 0;
    }
    Wx::Perl::ProcessStream::SetPollInterval( 100 );

    return 1;
}
sub set_stdout_call{
    my ($self, $name, $event) = @_;
    $self->{proc}->{$name}->{stdout} = $event;
}
sub set_exit_call{
    my ($self, $name, $event) = @_;
    $self->{proc}->{$name}->{exit} = $event;
}
sub set_error_call{
    my ($self, $name, $event) = @_;
    $self->{proc}->{$name}->{error} = $event;
}

sub addqueue{
    my ($self, %hash) = @_;
    if(defined $self->{proc}->{$hash{name}}){
        my $data = ${$hash{data}};
        return unless (defined $data);
        
        if(exists $self->{proc}->{$hash{name}}->{id}){
           $self->{proc}->{$hash{name}}->{id}++;
        }else{
            $self->{proc}->{$hash{name}}->{id} =0;
        }
        if(defined $data->{stdout}){
            $self->{proc}->{$hash{name}}->{ret}->{$self->{proc}->{$hash{name}}->{id}}{stdout} = $data->{stdout}; 
            delete $data->{stdout};
        }
        $data->{id} = $self->{proc}->{$hash{name}}->{id};
        my $string = JSON::XS->new->utf8->encode(${$hash{data}});
        
        $self->{proc}->{$hash{name}}->{proc}->WriteProcess($string."\n");
    }else{
        return;
    }
    
}
sub evt_stdout{
    my ($self, $event) = @_;
    $event->Skip(1);
    my $process = $event->GetProcess;
    my $name = $process->GetProcessName();
    $self->{proc}->{$name}->{stdoutbuf} = $process->GetStdOutBuffer;
    my $id;
    my $count = @{$self->{proc}->{$name}->{stdoutbuf}};
    while($count){
        $count--;
        my $data = shift @{$self->{proc}->{$name}->{stdoutbuf}};
        eval{$id =JSON::XS->new->utf8->decode($data)};
        #return 1 unless (defined $id->{id});
        if (defined $id->{id}){
            if (defined $self->{proc}->{$name}->{ret}->{$id->{id}}->{stdout}){
                my $code = $self->{proc}->{$name}->{ret}->{$id->{id}}->{stdout}->[1];
                ${$self->{proc}->{$name}->{ret}->{$id->{id}}->{stdout}->[0]}->$code(\$id);
                delete $self->{proc}->{$name}->{ret}->{$id->{id}};
            }else{
                if(defined $self->{proc}->{$name}->{stdout}){
                    my $code = $self->{proc}->{$name}->{stdout}->[1];
                    ${$self->{proc}->{$name}->{stdout}->[0]}->$code(\$id);
                }
            }
        }else{
            if(defined $self->{proc}->{$name}->{stdout}){
                my $code = $self->{proc}->{$name}->{stdout}->[1];
                ${$self->{proc}->{$name}->{stdout}->[0]}->$code(\$id);
            }
        } 
    }
     
}

sub evt_maxlines{
    my ($self, $event) = @_;
    $event->Skip(1);
    my $process = $event->GetProcess;
    if(defined $self->{$process->GetProcessName()}->{stdout}){
        $self->{$process->GetProcessName()}->{stdoutbuf} = $process->GetStdOutBuffer;
        $self->{$process->GetProcessName()}->{stdout}($self->{$process->GetProcessName()}->{stdoutbuf});
    }
    my $line = $event->GetLine;
}

sub evt_error{
    my ($self, $event) = @_;
    $event->Skip(1);
    my $process = $event->GetProcess;
    my $line = $event->GetLine;
}

sub evt_exit{
    my ($self, $event) = @_;
    $event->Skip(1);
    my $process = $event->GetProcess;
    my $line = $event->GetLine;
    my @buffers = @{ $process->GetStdOutBuffer };
    my @errors = @{ $process->GetStdErrBuffer };
    my $exitcode = $process->GetExitCode;
    $process->Destroy;
    
}
sub CloseProc{
    my $self = shift;
    my $name = shift;
    $self->{proc}->{$name}->{proc}->CloseInput();
    $self->{proc}->{$name}->{proc}->TerminateProcess();
    #$self->{proc}->{$name}->{proc}->KillProcess();
    delete $self->{proc}->{$name};
    
}

sub IsAlive{
    my $self = shift;
    my $name = shift;
    my $d = $self->{proc}->{$name}->{proc}->IsAlive();
    return $d;
}
sub deep_copy {
    my $this = shift;
    if (not ref $this) {
      $this;
    } elsif (ref $this eq "ARRAY") {
      [map deep_copy($_), @$this];
    } elsif (ref $this eq "HASH") {
      +{map { $_ => deep_copy($this->{$_}) } keys %$this};
    } else { die "what type is $_?" }
  }

sub Destroy{
    my ($self) = @_;
    
    foreach my $key(keys %{$self->{proc}}){
        $self->{proc}->{$key}->{proc}->CloseInput();
        $self->{proc}->{$key}->{proc}->KillProcess();
    }
    
}
1;
