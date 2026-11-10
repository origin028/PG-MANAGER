import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Building2, ArrowRight, ShieldCheck } from 'lucide-react';

export const HomePage: React.FC = () => {
  const [token, setToken] = useState('');
  const navigate = useNavigate();

  const handleGo = (e: React.FormEvent) => {
    e.preventDefault();
    if (token.trim()) {
      navigate(`/pay/${encodeURIComponent(token.trim())}`);
    }
  };

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col justify-center items-center p-4">
      <div className="w-full max-w-md bg-white rounded-2xl shadow-md border border-slate-200 overflow-hidden">
        <div className="bg-gradient-to-r from-blue-600 to-indigo-700 p-6 text-white text-center">
          <div className="inline-flex items-center justify-center p-3 bg-white/10 rounded-full mb-3">
            <Building2 className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-xl font-bold tracking-tight">Resident Payment Portal</h1>
          <p className="text-blue-100 text-xs mt-1">PG Management Secure Checkout</p>
        </div>

        <div className="p-6 md:p-8 space-y-6">
          <p className="text-slate-600 text-sm leading-relaxed text-center">
            This portal processes online invoice payments. When a payment link is issued to a resident, they access their checkout page via a secure token.
          </p>

          <form onSubmit={handleGo} className="space-y-3">
            <label className="block text-xs font-semibold text-slate-500 uppercase tracking-wider">
              Enter Payment Token
            </label>
            <div className="flex gap-2">
              <input
                type="text"
                placeholder="e.g. demo-token"
                value={token}
                onChange={(e) => setToken(e.target.value)}
                className="flex-1 px-3 py-2 border border-slate-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono"
              />
              <button
                type="submit"
                disabled={!token.trim()}
                className="px-4 py-2 bg-blue-600 hover:bg-blue-700 disabled:bg-blue-300 text-white rounded-lg text-sm font-medium transition-colors flex items-center gap-1"
              >
                <span>Go</span>
                <ArrowRight className="w-4 h-4" />
              </button>
            </div>
          </form>

          <div className="border-t border-slate-100 pt-4">
            <p className="text-xs text-slate-500 mb-2 font-medium">Quick Demo Links:</p>
            <div className="flex flex-wrap gap-2">
              <button
                onClick={() => navigate('/pay/demo-checkout-token')}
                className="text-xs px-3 py-1.5 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-md font-mono transition-colors"
              >
                /pay/demo-checkout-token
              </button>
            </div>
          </div>

          <div className="flex items-center justify-center space-x-2 text-xs text-slate-400 pt-2 border-t border-slate-100">
            <ShieldCheck className="w-4 h-4 text-emerald-600" />
            <span>256-Bit Encrypted Payment Gateway</span>
          </div>
        </div>
      </div>
    </div>
  );
};

