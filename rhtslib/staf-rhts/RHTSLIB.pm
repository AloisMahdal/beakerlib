#############################################################################
# Ray Chen <chenrano2002@163.com>
#
# This software is licensed under the Eclipse Public License (EPL) V1.0.    #
#############################################################################

package RHTSLIB;

use PLSTAFService;
use PLSTAF;
use STAFLog;
use 5.008;
use threads;
use threads::shared;
use Thread::Queue;
use Data::Dumper;

use strict;
use warnings;

use constant kRHTSLIBInvalidNumber => scalar 4001;
use constant kVersion => scalar "0.0.1";

# In this queue the master threads queue jobs for the slave worker
my $work_queue = new Thread::Queue;
my $free_workers : shared = 0;

our $fServiceName;         # passed in part of parms
our $fHandle;               # staf handle for service
our $fAddParser ;          # .
our $fLineSep;
our $fLogHandle;

#sub Construct
#{
#    my $result = $fLogHandle->log("DEBUG", "Enter Construct function");
#}

sub new
{
    my ($class, $info) = @_;

    my $self =
    {
        threads_list => [],
        worker_created => 0,
        max_workers => 5, # do not create more than 5 workers
    };
    # Here, %info = ( ServiceType  => "the type of service", 
    #                        ServiceName => "name",
    #                        Params         => "parameters that have been passed to the 
    #                                                  service (via the PARMS option)",
    #                       WriteLocation => "The name of the root directory where the service 
    #                                                   should write all service-related data (if it has any)",
   #              )

    $fServiceName = $info->{ServiceName};

    $fHandle = STAF::STAFHandle->new("STAF/Service/" . $fServiceName);

    # Load Log service
    $fLogHandle = STAF::STAFLog->new($fHandle, "rhts","GLOBAL", "INFO");
    $fLogHandle->log("DEBUG", "Enter new function");

    # Add Parser
    $fAddParser = STAFCommandParser->new();

    my $lineSepResult = $fHandle->submit2($STAF::STAFHandle::kReqSync,
        "local", "var", "resolve string {STAF/Config/Sep/Line}");

    $fLineSep = $lineSepResult->{result};

    return bless $self, $class;
}

#The service is active and ready to accept requests 
sub AcceptRequest
{
    my ($self, $info) = @_;
    my %hash : shared = %$info;

    #print_dump($fLogHandle, "self", $self);
    #print_dump($fLogHandle, "RequestHash", \%hash);

    if ($free_workers <= 0 and
        $self->{worker_created} < $self->{max_workers})
    {
        my $thr = threads->create(\&Worker);
        push @{ $self->{threads_list} }, $thr;
        $self->{worker_created}++;
    }
    else
    {
        lock $free_workers;
        $free_workers--;
    }

    $work_queue->enqueue(\%hash);

    return $STAF::DelayedAnswer;
}

sub Worker
{
    my $loop_flag = 1;

    while ($loop_flag)
    {
        eval
        {
            # get the work from the queue
            my $hash_ref = $work_queue->dequeue();

            if (not ref($hash_ref) and $hash_ref->{request} eq 'stop')
            {
                $loop_flag = 0;
                return;
            }

            my ($rc, $result) = handleRequest($hash_ref);

            STAF::DelayedAnswer($hash_ref->{requestNumber}, $rc, $result);

            # increase the number of free threads
            {
                lock $free_workers;
                $free_workers++;
            }
        }
    }

    return 1;
}


sub handleRequest
{
    my $info = shift;

    print_dump($fLogHandle, "RequestInfo", $info);

    my $lowerRequest = lc($info->{request});
    my $requestType = "";

    # get first "word" in request
    if($lowerRequest =~ m/\b(\w*)\b/)
    {
        $requestType = $&;
    }
    else
    {
        return (STAFResult::kInvalidRequestString,
            "Unknown DeviceService Request: " . ($info->{request}));
    }

    if ($requestType eq "list")
    {
        #return handleList($info);
    }
    elsif ($requestType eq "query")
    {
        #return handleQuery($info);
    }
    elsif ($requestType eq "help")
    {
        return handleHelp();
    }
    elsif ($requestType eq "version")
    {
        return handleVersion();
    }
    else
    {
        return (STAFResult::kInvalidRequestString,
            "Unknown DeviceService Request: " . $info->{request});
    }

    return (0, "");
}

sub handleVersion
{
    return (STAFResult::kOk, kVersion);
}

sub handleHelp
{
    return (STAFResult::kOk,
          "RHTSLIB Service Help" . $fLineSep
          . $fLineSep . "VERSION" . $fLineSep . "HELP");

}


#Termination/Destruction Phase
sub DESTROY
{
    my ($self) = @_;

    #$fLogHandle->log("DEBUG", "destroy");
    # Ask all the threads to stop, and join them.
    for my $thr (@{ $self->{threads_list} })
    {
        $work_queue->enqueue('stop');
    }

    # perform any cleanup for the service here

    #unregisterHelpData(kRHTSLIBInvalidNumber);

    #Un-register the service handle
    $fHandle->unRegister();
}


###############################################################################
#                           Local service function
###############################################################################
sub print_dump
{
    my ($logfd, $data_name, $data_ref) = @_;

    # config data dumper
    $Data::Dumper::Terse = 0;
    my $dump_name = '*' . "$data_name";
    my $dump_data = Data::Dumper->Dump([$data_ref], [$dump_name]);

    $logfd->log("DEBUG", $dump_data);
    
    return;
}

###############################################################################
1;  # require expects this module to return true (!0)
###############################################################################
