import React, { useEffect, useState, useRef } from 'react';
import { useParams } from 'react-router-dom';
import {
  Building2,
  Calendar,
  CreditCard,
  AlertCircle,
  Clock,
  CheckCircle2,
  ShieldCheck,
  RefreshCw,
  DoorOpen,
  ReceiptText
} from 'lucide-react';
import { PublicCheckoutDetails, APIResponse } from '../types/payment';
import { loadRazorpayScript } from '../utils/razorpay';

export const ResidentCheckoutPage: React.FC = () => {
  const { token } = useParams<{ token: string }>();

  const [loading, setLoading] = useState<boolean>(true);
  const [details, setDetails] = useState<PublicCheckoutDetails | null>(null);
  const [errorStatus, setErrorStatus] = useState<number | null>(null);
  const [errorMessage, setErrorMessage] = useState<string>('');
  const [isProcessing, setIsProcessing] = useState<boolean>(false);
  const [paymentCompleted, setPaymentCompleted] = useState<boolean>(false);

  // Prevent multiple simultaneous clicks opening Razorpay modal
  const checkoutLock = useRef<boolean>(false);

  const fetchCheckoutDetails = async () => {
    if (!token) {
      setErrorStatus(400);
      setErrorMessage('Missing payment token in URL.');
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      setErrorStatus(null);
      setErrorMessage('');

      // Base API URL: when VITE_API_BASE_URL is not provided, defaults to empty string ""
      // so relative requests (/api/v1/...) work with reverse proxies routing /api to the backend.
      const rawBaseUrl = import.meta.env.VITE_API_BASE_URL || '';
      const baseUrl = rawBaseUrl.replace(/\/+$/, '');
      const res = await fetch(`${baseUrl}/api/v1/payments/links/${token}/checkout`);
      const body: APIResponse<PublicCheckoutDetails> = await res.json();

      if (!res.ok) {
        setErrorStatus(res.status);
        const msg = body.error?.message || body.message || 'Unable to load payment details.';
        setErrorMessage(msg);
        return;
      }

      if (body.data) {
        setDetails(body.data);
      }
    } catch (err: any) {
      setErrorStatus(0); // Network error
      setErrorMessage('Unable to connect to payment server. Please check your network connection.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchCheckoutDetails();
  }, [token]);

  const handlePayNow = async () => {
    if (!details || checkoutLock.current || isProcessing) return;

    checkoutLock.current = true;
    setIsProcessing(true);

    try {
      const scriptLoaded = await loadRazorpayScript();
      if (!scriptLoaded) {
        alert('Failed to load secure Razorpay checkout SDK. Please check your internet connection and try again.');
        setIsProcessing(false);
        checkoutLock.current = false;
        return;
      }

      const options = {
        key: details.key_id,
        amount: details.amount_paise,
        currency: details.currency,
        name: details.property_name,
        description: `Rent payment for Room ${details.room_number} (${details.billing_month})`,
        order_id: details.gateway_order_id,
        handler: function () {
          // Client-side UI acknowledgment only: server webhook is the authority
          setPaymentCompleted(true);
          setIsProcessing(false);
          checkoutLock.current = false;
        },
        modal: {
          ondismiss: function () {
            setIsProcessing(false);
            checkoutLock.current = false;
          },
        },
        theme: {
          color: '#2563eb', // Blue-600
        },
      };

      const rzp = new window.Razorpay(options);
      rzp.open();
    } catch (err) {
      setIsProcessing(false);
      checkoutLock.current = false;
    }
  };

  // 1. Loading State
  if (loading) {
    return (
      <div className="min-h-screen bg-slate-50 flex flex-col justify-center items-center p-4">
        <div className="w-full max-w-md bg-white rounded-2xl shadow-sm border border-slate-200 p-8 text-center animate-pulse">
          <div className="h-12 w-12 bg-blue-100 text-blue-600 rounded-full mx-auto flex items-center justify-center mb-4">
            <RefreshCw className="w-6 h-6 animate-spin" />
          </div>
          <div className="h-6 bg-slate-200 rounded w-3/4 mx-auto mb-3"></div>
          <div className="h-4 bg-slate-100 rounded w-1/2 mx-auto"></div>
        </div>
      </div>
    );
  }

  // 2. Error States (Expired, Invalid, Already Paid, Network Error)
  if (errorStatus !== null || !details) {
    const isExpired = errorStatus === 409 && errorMessage.toLowerCase().includes('expired');
    const isAlreadyPaid = errorStatus === 409 && errorMessage.toLowerCase().includes('already');
    const isNotFound = errorStatus === 404;

    return (
      <div className="min-h-screen bg-slate-50 flex flex-col justify-center items-center p-4">
        <div className="w-full max-w-md bg-white rounded-2xl shadow-sm border border-slate-200 p-6 md:p-8 text-center">
          <div className={`w-14 h-14 rounded-full mx-auto flex items-center justify-center mb-4 ${
            isAlreadyPaid ? 'bg-emerald-100 text-emerald-600' : isExpired ? 'bg-amber-100 text-amber-600' : 'bg-rose-100 text-rose-600'
          }`}>
            {isAlreadyPaid ? (
              <CheckCircle2 className="w-8 h-8" />
            ) : isExpired ? (
              <Clock className="w-8 h-8" />
            ) : (
              <AlertCircle className="w-8 h-8" />
            )}
          </div>

          <h2 className="text-xl font-semibold text-slate-800 mb-2">
            {isAlreadyPaid
              ? 'Payment Already Received'
              : isExpired
              ? 'Payment Link Expired'
              : isNotFound
              ? 'Invalid Payment Link'
              : 'Payment Unavailable'}
          </h2>

          <p className="text-slate-600 text-sm mb-6">
            {errorMessage || 'This payment link cannot be accessed at this time. Please contact your PG manager.'}
          </p>

          <button
            onClick={fetchCheckoutDetails}
            className="inline-flex items-center justify-center px-4 py-2 border border-slate-300 text-sm font-medium rounded-lg text-slate-700 bg-white hover:bg-slate-50 transition-colors shadow-sm"
          >
            <RefreshCw className="w-4 h-4 mr-2" /> Retry
          </button>
        </div>
      </div>
    );
  }

  // 3. Pending Settlement State (Shown after Razorpay modal completes)
  if (paymentCompleted) {
    return (
      <div className="min-h-screen bg-slate-50 flex flex-col justify-center items-center p-4">
        <div className="w-full max-w-md bg-white rounded-2xl shadow-sm border border-slate-200 p-6 md:p-8 text-center">
          <div className="w-14 h-14 bg-blue-100 text-blue-600 rounded-full mx-auto flex items-center justify-center mb-4">
            <ShieldCheck className="w-8 h-8" />
          </div>

          <h2 className="text-xl font-bold text-slate-900 mb-2">Payment Verification in Progress</h2>
          <p className="text-slate-600 text-sm mb-6">
            Your transaction has been submitted to the gateway. Our system is verifying the webhook notification to update your invoice and issue your official receipt.
          </p>

          <div className="bg-slate-50 rounded-xl p-4 text-left border border-slate-200 mb-6 text-sm">
            <div className="flex justify-between py-1">
              <span className="text-slate-500">Invoice:</span>
              <span className="font-medium text-slate-800">{details.invoice_number}</span>
            </div>
            <div className="flex justify-between py-1">
              <span className="text-slate-500">Amount:</span>
              <span className="font-semibold text-slate-900">₹{Number(details.amount).toFixed(2)}</span>
            </div>
          </div>

          <button
            onClick={() => {
              setPaymentCompleted(false);
              fetchCheckoutDetails();
            }}
            className="w-full py-2.5 px-4 bg-slate-800 text-white rounded-xl font-medium text-sm hover:bg-slate-900 transition-colors"
          >
            Refresh Status
          </button>
        </div>
      </div>
    );
  }

  // 4. Default Ready to Pay State
  const formattedAmount = Number(details.amount).toLocaleString('en-IN', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });

  const expiresDate = new Date(details.expires_at);

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col justify-center items-center p-4">
      <div className="w-full max-w-md bg-white rounded-2xl shadow-md border border-slate-200 overflow-hidden">
        {/* Header */}
        <div className="bg-gradient-to-r from-blue-600 to-indigo-700 p-6 text-white text-center">
          <div className="inline-flex items-center justify-center p-2 bg-white/10 rounded-full mb-3">
            <Building2 className="w-6 h-6 text-white" />
          </div>
          <h1 className="text-xl font-bold tracking-tight">{details.property_name}</h1>
          <p className="text-blue-100 text-xs mt-1">Official Resident Payment Portal</p>
        </div>

        {/* Invoice Body */}
        <div className="p-6 md:p-8 space-y-6">
          <div className="text-center">
            <span className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Amount Due</span>
            <div className="text-4xl font-extrabold text-slate-900 mt-1">
              ₹{formattedAmount}
            </div>
          </div>

          <div className="bg-slate-50 rounded-xl p-4 border border-slate-100 space-y-3 text-sm">
            <div className="flex items-center justify-between">
              <span className="text-slate-500 flex items-center">
                <DoorOpen className="w-4 h-4 mr-2 text-slate-400" /> Room
              </span>
              <span className="font-medium text-slate-800">{details.room_number}</span>
            </div>

            <div className="flex items-center justify-between">
              <span className="text-slate-500 flex items-center">
                <ReceiptText className="w-4 h-4 mr-2 text-slate-400" /> Invoice Number
              </span>
              <span className="font-mono text-xs font-medium text-slate-800">{details.invoice_number}</span>
            </div>

            <div className="flex items-center justify-between">
              <span className="text-slate-500 flex items-center">
                <Calendar className="w-4 h-4 mr-2 text-slate-400" /> Billing Cycle
              </span>
              <span className="font-medium text-slate-800">{details.billing_month}</span>
            </div>

            <div className="flex items-center justify-between pt-2 border-t border-slate-200/60">
              <span className="text-slate-500 flex items-center text-xs">
                <Clock className="w-3.5 h-3.5 mr-1.5 text-slate-400" /> Valid Until
              </span>
              <span className="text-xs text-slate-600 font-medium">
                {expiresDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
              </span>
            </div>
          </div>

          {/* Secure Trust Badge */}
          <div className="flex items-center justify-center space-x-2 text-xs text-slate-500">
            <ShieldCheck className="w-4 h-4 text-emerald-600" />
            <span>256-Bit Encrypted • UPI, Cards & NetBanking</span>
          </div>

          {/* Action Button */}
          <button
            onClick={handlePayNow}
            disabled={isProcessing}
            data-testid="pay-now-button"
            className="w-full py-3.5 px-4 bg-blue-600 hover:bg-blue-700 disabled:bg-blue-400 text-white font-semibold rounded-xl shadow-sm transition-all duration-150 flex items-center justify-center space-x-2"
          >
            {isProcessing ? (
              <>
                <RefreshCw className="w-5 h-5 animate-spin" />
                <span>Launching Checkout...</span>
              </>
            ) : (
              <>
                <CreditCard className="w-5 h-5" />
                <span>Pay ₹{formattedAmount}</span>
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
};
